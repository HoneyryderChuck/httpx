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
      @parser = Parser::HTTP1.new
      @parser.on(:start, &method(:on_message_begin))
      @parser.on(:headers, &method(:on_headers_complete))
      @parser.on(:trailers, &method(:on_trailer_headers_complete))
      @parser.on(:data, &method(:on_body))
      @parser.on(:complete, &method(:on_message_complete))
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
      if @requests.size >= @max_concurrent_requests
        @pending << request
        return
      end
      @requests << request unless @requests.include?(request)
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

    def on_message_begin
      log(level: 2) { "parsing begins" }
    end

    def on_headers_complete(h)
      # Wait for fix: https://github.com/tmm1/http_parser.rb/issues/52
      # callback is called 2 times when chunked
      request = @requests.first
      return if request.response

      log(level: 2) { "headers received" }
      headers = @options.headers_class.new(h)
      response = @options.response_class.new(@requests.last,
                                             @parser.status_code,
                                             @parser.http_version.join("."),
                                             headers, @options)
      log(color: :yellow) { "-> HEADLINE: #{response.status} HTTP/#{@parser.http_version.join(".")}" }
      log(color: :yellow) { response.headers.each.map { |f, v| "-> HEADER: #{f}: #{v}" }.join("\n") }

      request.response = response
      dispatch if request.verb == :head
    end

    def on_trailer_headers_complete(h)
      response = @requests.first.response
      log(level: 2) { "trailer headers received" }

      log(color: :yellow) { h.each.map { |f, v| "-> HEADER: #{f}: #{v}" }.join("\n") }
      response.merge_headers(h)
    end

    def on_body(chunk)
      log(color: :green) { "-> DATA: #{chunk.bytesize} bytes..." }
      log(level: 2, color: :green) { "-> #{chunk.inspect}" }
      response = @requests.first.response

      response << chunk
    end

    def on_message_complete
      log(level: 2) { "parsing complete" }
      dispatch
    end


    def dispatch
      request = @requests.first
      if request.expects?
        reset
        return handle(request)
      end

      @requests.shift
      response = request.response
      emit(:response, request, response)

      if @parser.upgrade?
        response << @parser.upgrade_data
        throw(:called)
      end
      reset
      send(@pending.shift) unless @pending.empty?
      return unless response.headers["connection"] == "close"
      disable_concurrency
      emit(:reset)
    end

    def handle_error(ex)
      @requests.each do |request|
        emit(:error, request, ex)
      end
    end

    private

    def disable_concurrency
      return if @requests.empty?
      @requests.each { |r| r.transition(:idle) }
      # server doesn't handle pipelining, and probably
      # doesn't support keep-alive. Fallback to send only
      # 1 keep alive request.
      @max_concurrent_requests = 1
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
