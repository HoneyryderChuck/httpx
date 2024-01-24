# frozen_string_literal: true

require "httpx/parser/http1"

module HTTPX
  class Connection::HTTP1
    include Callbacks
    include Loggable

    MAX_REQUESTS = 200
    CRLF = "\r\n"

    attr_reader :pending, :requests

    attr_accessor :max_concurrent_requests

    def initialize(buffer, options)
      @options = options
      @max_concurrent_requests = @options.max_concurrent_requests || MAX_REQUESTS
      @max_requests = @options.max_requests
      @parser = Parser::HTTP1.new(self)
      @buffer = buffer
      @version = [1, 1]
      @pending = []
      @requests = []
      @handshake_completed = false
    end

    def timeout
      @options.timeout[:operation_timeout]
    end

    def interests
      # this means we're processing incoming response already
      return :r if @request

      return if @requests.empty?

      request = @requests.first

      return unless request

      return :w if request.interests == :w || !@buffer.empty?

      :r
    end

    def reset
      @max_requests = @options.max_requests || MAX_REQUESTS
      @parser.reset!
      @handshake_completed = false
      @pending.concat(@requests) unless @requests.empty?
    end

    def close
      reset
      emit(:close, true)
    end

    def exhausted?
      !@max_requests.positive?
    end

    def empty?
      # this means that for every request there's an available
      # partial response, so there are no in-flight requests waiting.
      @requests.empty? || (
        # checking all responses can be time-consuming. Alas, as in HTTP/1, responses
        # do not come out of order, we can get away with checking first and last.
        !@requests.first.response.nil? &&
        (@requests.size == 1 || !@requests.last.response.nil?)
      )
    end

    def <<(data)
      @parser << data
    end

    def send(request)
      unless @max_requests.positive?
        @pending << request
        return
      end

      return if @requests.include?(request)

      @requests << request
      @pipelining = true if @requests.size > 1
    end

    def consume
      requests_limit = [@max_requests, @requests.size].min
      concurrent_requests_limit = [@max_concurrent_requests, requests_limit].min
      @requests.each_with_index do |request, idx|
        break if idx >= concurrent_requests_limit
        next if request.state == :done

        handle(request)
      end
    end

    # HTTP Parser callbacks
    #
    # must be public methods, or else they won't be reachable

    def on_start
      log(level: 2) { "parsing begins" }
    end

    def on_headers(h)
      @request = @requests.first

      return if @request.response

      log(level: 2) { "headers received" }
      headers = @request.options.headers_class.new(h)
      response = @request.options.response_class.new(@request,
                                                     @parser.status_code,
                                                     @parser.http_version.join("."),
                                                     headers)
      log(color: :yellow) { "-> HEADLINE: #{response.status} HTTP/#{@parser.http_version.join(".")}" }
      log(color: :yellow) { response.headers.each.map { |f, v| "-> HEADER: #{f}: #{v}" }.join("\n") }

      @request.response = response
      on_complete if response.finished?
    end

    def on_trailers(h)
      return unless @request

      response = @request.response
      log(level: 2) { "trailer headers received" }

      log(color: :yellow) { h.each.map { |f, v| "-> HEADER: #{f}: #{v.join(", ")}" }.join("\n") }
      response.merge_headers(h)
    end

    def on_data(chunk)
      request = @request

      return unless request

      log(color: :green) { "-> DATA: #{chunk.bytesize} bytes..." }
      log(level: 2, color: :green) { "-> #{chunk.inspect}" }
      response = request.response

      response << chunk
    rescue StandardError => e
      error_response = ErrorResponse.new(request, e, request.options)
      request.response = error_response
      dispatch
    end

    def on_complete
      request = @request

      return unless request

      log(level: 2) { "parsing complete" }
      dispatch
    end

    def dispatch
      request = @request

      if request.expects?
        @parser.reset!
        return handle(request)
      end

      @request = nil
      @requests.shift
      response = request.response
      response.finish! unless response.is_a?(ErrorResponse)
      emit(:response, request, response)

      if @parser.upgrade?
        response << @parser.upgrade_data
        throw(:called)
      end

      @parser.reset!
      @max_requests -= 1
      if response.is_a?(ErrorResponse)
        disable
      else
        manage_connection(request, response)
      end

      if exhausted?
        @pending.concat(@requests)
        @requests.clear

        emit(:exhausted)
      else
        send(@pending.shift) unless @pending.empty?
      end
    end

    def handle_error(ex)
      if (ex.is_a?(EOFError) || ex.is_a?(TimeoutError)) && @request && @request.response &&
         !@request.response.headers.key?("content-length") &&
         !@request.response.headers.key?("transfer-encoding")
        # if the response does not contain a content-length header, the server closing the
        # connnection is the indicator of response consumed.
        # https://greenbytes.de/tech/webdav/rfc2616.html#rfc.section.4.4
        catch(:called) { on_complete }
        return
      end

      if @pipelining
        catch(:called) { disable }
      else
        @requests.each do |request|
          emit(:error, request, ex)
        end
        @pending.each do |request|
          emit(:error, request, ex)
        end
      end
    end

    def ping
      reset
      emit(:reset)
      emit(:exhausted)
    end

    private

    def manage_connection(request, response)
      connection = response.headers["connection"]
      case connection
      when /keep-alive/i
        if @handshake_completed
          if @max_requests.zero?
            @pending.concat(@requests)
            @requests.clear
            emit(:exhausted)
          end
          return
        end

        keep_alive = response.headers["keep-alive"]
        return unless keep_alive

        parameters = Hash[keep_alive.split(/ *, */).map do |pair|
          pair.split(/ *= */, 2)
        end]
        @max_requests = parameters["max"].to_i - 1 if parameters.key?("max")

        if parameters.key?("timeout")
          keep_alive_timeout = parameters["timeout"].to_i
          emit(:timeout, keep_alive_timeout)
        end
        @handshake_completed = true
      when /close/i
        disable
      when nil
        # In HTTP/1.1, it's keep alive by default
        return if response.version == "1.1" && request.headers["connection"] != "close"

        disable
      end
    end

    def disable
      disable_pipelining
      reset
      emit(:reset)
      throw(:called)
    end

    def disable_pipelining
      return if @requests.empty?
      # do not disable pipelining if already set to 1 request at a time
      return if @max_concurrent_requests == 1

      @requests.each do |r|
        r.transition(:idle)

        # when we disable pipelining, we still want to try keep-alive.
        # only when keep-alive with one request fails, do we fallback to
        # connection: close.
        r.headers["connection"] = "close" if @max_concurrent_requests == 1
      end
      # server doesn't handle pipelining, and probably
      # doesn't support keep-alive. Fallback to send only
      # 1 keep alive request.
      @max_concurrent_requests = 1
      @pipelining = false
    end

    def set_protocol_headers(request)
      if !request.headers.key?("content-length") &&
         request.body.bytesize == Float::INFINITY
        request.body.chunk!
      end

      extra_headers = {}

      unless request.headers.key?("connection")
        connection_value = if request.persistent?
          # when in a persistent connection, the request can't be at
          # the edge of a renegotiation
          if @requests.index(request) + 1 < @max_requests
            "keep-alive"
          else
            "close"
          end
        else
          # when it's not a persistent connection, it sets "Connection: close" always
          # on the last request of the possible batch (either allowed max requests,
          # or if smaller, the size of the batch itself)
          requests_limit = [@max_requests, @requests.size].min
          if request == @requests[requests_limit - 1]
            "close"
          else
            "keep-alive"
          end
        end

        extra_headers["connection"] = connection_value
      end
      extra_headers["host"] = request.authority unless request.headers.key?("host")
      extra_headers
    end

    def handle(request)
      catch(:buffer_full) do
        request.transition(:headers)
        join_headers(request) if request.state == :headers
        request.transition(:body)
        join_body(request) if request.state == :body
        request.transition(:trailers)
        # HTTP/1.1 trailers should only work for chunked encoding
        join_trailers(request) if request.body.chunked? && request.state == :trailers
        request.transition(:done)
      end
    end

    def join_headline(request)
      "#{request.verb} #{request.path} HTTP/#{@version.join(".")}"
    end

    def join_headers(request)
      headline = join_headline(request)
      @buffer << headline << CRLF
      log(color: :yellow) { "<- HEADLINE: #{headline.chomp.inspect}" }
      extra_headers = set_protocol_headers(request)
      join_headers2(request.headers.each(extra_headers))
      log { "<- " }
      @buffer << CRLF
    end

    def join_body(request)
      return if request.body.empty?

      while (chunk = request.drain_body)
        log(color: :green) { "<- DATA: #{chunk.bytesize} bytes..." }
        log(level: 2, color: :green) { "<- #{chunk.inspect}" }
        @buffer << chunk
        throw(:buffer_full, request) if @buffer.full?
      end

      return unless (error = request.drain_error)

      raise error
    end

    def join_trailers(request)
      return unless request.trailers? && request.callbacks_for?(:trailers)

      join_headers2(request.trailers)
      log { "<- " }
      @buffer << CRLF
    end

    def join_headers2(headers)
      headers.each do |field, value|
        buffer = "#{capitalized(field)}: #{value}#{CRLF}"
        log(color: :yellow) { "<- HEADER: #{buffer.chomp}" }
        @buffer << buffer
      end
    end

    UPCASED = {
      "www-authenticate" => "WWW-Authenticate",
      "http2-settings" => "HTTP2-Settings",
      "content-md5" => "Content-MD5",
    }.freeze

    def capitalized(field)
      UPCASED[field] || field.split("-").map(&:capitalize).join("-")
    end
  end
end
