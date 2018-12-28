# frozen_string_literal: true

require "httpx/parser/http1"

module HTTPX
  class Channel::HTTP1
    include Callbacks
    include Loggable

    CRLF = "\r\n"

    def initialize(buffer, options)
      @options = Options.new(options)
      @max_concurrent_requests = @options.max_concurrent_requests
      @max_requests = Float::INFINITY
      @parser = Parser::HTTP1.new(self)
      @buffer = buffer
      @version = [1, 1]
      @pending = []
      @requests = []
    end

    def reset
      @parser.reset!
    end

    def close
      reset
      emit(:close)
    end

    def empty?
      # this means that for every request there's an available
      # partial response, so there are no in-flight requests waiting.
      @requests.empty? || @requests.all? { |request| !request.response.nil? }
    end

    def <<(data)
      @parser << data
    end

    def send(request, **)
      if @max_requests.positive? &&
         @requests.size >= @max_concurrent_requests
        @pending << request
        return
      end
      unless @requests.include?(request)
        @requests << request
        @pipelining = true if @requests.size > 1
      end
      handle(request)
    end

    def reenqueue!
      requests = @requests.dup
      @requests.clear
      requests.each do |request|
        send(request)
      end
    end

    def consume
      @requests.each do |request|
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
      headers = @options.headers_class.new(h)
      response = @options.response_class.new(@request,
                                             @parser.status_code,
                                             @parser.http_version.join("."),
                                             headers, @options)
      log(color: :yellow) { "-> HEADLINE: #{response.status} HTTP/#{@parser.http_version.join(".")}" }
      log(color: :yellow) { response.headers.each.map { |f, v| "-> HEADER: #{f}: #{v}" }.join("\n") }

      @request.response = response
      on_complete if response.complete?
    end

    def on_trailers(h)
      return unless @request

      response = @request.response
      log(level: 2) { "trailer headers received" }

      log(color: :yellow) { h.each.map { |f, v| "-> HEADER: #{f}: #{v}" }.join("\n") }
      response.merge_headers(h)
    end

    def on_data(chunk)
      return unless @request

      log(color: :green) { "-> DATA: #{chunk.bytesize} bytes..." }
      log(level: 2, color: :green) { "-> #{chunk.inspect}" }
      response = @request.response

      response << chunk
    end

    def on_complete
      return unless @request

      log(level: 2) { "parsing complete" }
      dispatch
    end

    def dispatch
      if @request.expects?
        reset
        return handle(@request)
      end

      request = @request
      @request = nil
      @requests.shift
      response = request.response
      emit(:response, request, response)

      if @parser.upgrade?
        response << @parser.upgrade_data
        throw(:called)
      end

      reset
      @max_requests -= 1
      send(@pending.shift) unless @pending.empty?
      manage_connection(response)
    end

    def handle_error(ex)
      if @pipelining
        disable_pipelining
        emit(:reset)
        throw(:called)
      else
        @requests.each do |request|
          emit(:error, request, ex)
        end
      end
    end

    private

    def manage_connection(response)
      connection = response.headers["connection"]
      case connection
      when /keep\-alive/i
        keep_alive = response.headers["keep-alive"]
        return unless keep_alive

        parameters = Hash[keep_alive.split(/ *, */).map do |pair|
          pair.split(/ *= */)
        end]
        @max_requests = parameters["max"].to_i if parameters.key?("max")
        if parameters.key?("timeout")
          keep_alive_timeout = parameters["timeout"].to_i
          emit(:timeout, keep_alive_timeout)
        end
        # TODO: on keep alive timeout, reset
      when /close/i, nil
        disable_pipelining
        @max_requests = Float::INFINITY
        emit(:reset)
      end
    end

    def disable_pipelining
      return if @requests.empty?

      @requests.each { |r| r.transition(:idle) }
      # server doesn't handle pipelining, and probably
      # doesn't support keep-alive. Fallback to send only
      # 1 keep alive request.
      @max_concurrent_requests = 1
      @pipelining = false
    end

    def set_request_headers(request)
      request.headers["host"] ||= request.authority
      request.headers["connection"] ||= "keep-alive"
      if !request.headers.key?("content-length") &&
         request.body.bytesize == Float::INFINITY
        request.chunk!
      end
    end

    def headline_uri(request)
      request.path
    end

    def handle(request)
      set_request_headers(request)
      catch(:buffer_full) do
        request.transition(:headers)
        join_headers(request) if request.state == :headers
        request.transition(:body)
        join_body(request) if request.state == :body
        request.transition(:done)
      end
    end

    def join_headers(request)
      buffer = +""
      buffer << "#{request.verb.to_s.upcase} #{headline_uri(request)} HTTP/#{@version.join(".")}" << CRLF
      log(color: :yellow) { "<- HEADLINE: #{buffer.chomp.inspect}" }
      @buffer << buffer
      buffer.clear
      request.headers.each do |field, value|
        buffer << "#{capitalized(field)}: #{value}" << CRLF
        log(color: :yellow) { "<- HEADER: #{buffer.chomp}" }
        @buffer << buffer
        buffer.clear
      end
      log { "<- " }
      @buffer << CRLF
    end

    def join_body(request)
      return if request.empty?

      while (chunk = request.drain_body)
        log(color: :green) { "<- DATA: #{chunk.bytesize} bytes..." }
        log(level: 2, color: :green) { "<- #{chunk.inspect}" }
        @buffer << chunk
        throw(:buffer_full, request) if @buffer.full?
      end
    end

    UPCASED = {
      "www-authenticate" => "WWW-Authenticate",
      "http2-settings" => "HTTP2-Settings",
    }.freeze

    def capitalized(field)
      UPCASED[field] || field.to_s.split("-").map(&:capitalize).join("-")
    end
  end
  Channel.register "http/1.1", Channel::HTTP1
end
