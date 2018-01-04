# frozen_string_literal: true

require "http_parser"

module HTTPX
  class Channel::HTTP1
    include Callbacks

    CRLF = "\r\n"

    def initialize(buffer, options)
      @options = Options.new(options)
      @max_concurrent_requests = @options.max_concurrent_requests
      @parser = HTTP::Parser.new(self)
      @parser.header_value_type = :arrays
      @buffer = buffer
      @version = [1,1]
      @pending = []  
      @requests = []
    end

    def close 
      @parser.reset! 
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
      log(2) { "parsing begins" }
    end

    def on_headers_complete(h)
      # Wait for fix: https://github.com/tmm1/http_parser.rb/issues/52
      # callback is called 2 times when chunked
      request = @requests.first
      return if request.response

      log(2) { "headers received" }
      headers = @options.headers_class.new(h)
      response = @options.response_class.new(@requests.last, @parser.status_code, headers, @options)
      log { "-> HEADLINE: #{response.status} HTTP/#{@parser.http_version.join(".")}" } 
      log { response.headers.each.map { |f, v| "-> HEADER: #{f}: #{v}" }.join("\n") }
      
      request.response = response
      # parser can't say if it's parsing GET or HEAD,
      # call the completeness callback manually
      on_message_complete if request.verb == :head ||
                             request.verb == :connect
    end

    def on_body(chunk)
      log { "-> DATA: #{chunk.bytesize} bytes..." }
      log(2) { "-> #{chunk.inspect}" }
      @requests.first.response << chunk
    end

    def on_message_complete
      log(2) { "parsing complete" }
      @parser.reset!
      request = @requests.first
      return handle(request) if request.expects?

      @requests.shift
      response = request.response
      emit(:response, request, response)

      send(@pending.shift) unless @pending.empty?
      if response.headers["connection"] == "close"
        unless @requests.empty?
          @requests.map { |r| r.transition(:idle) }
          # server doesn't handle pipelining, and probably
          # doesn't support keep-alive. Fallback to send only
          # 1 keep alive request. 
          @max_concurrent_requests = 1
        end
        log(2) { "connection: close" }
        emit(:close)
      end
    end

    private

    def set_request_headers(request)
      request.headers["host"] ||= request.authority 
      request.headers["connection"] ||= "keep-alive"
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
      log { "<- HEADLINE: #{buffer.chomp.inspect}" }
      @buffer << buffer
      buffer.clear
      request.headers.each do |field, value|
        buffer << "#{capitalized(field)}: #{value}" << CRLF 
        log { "<- HEADER: #{buffer.chomp.inspect}" }
        @buffer << buffer
        buffer.clear
      end
      log { "<- " }
      @buffer << CRLF
    end

    def join_body(request)
      return if request.empty?
      while chunk = request.drain_body
        log { "<- DATA: #{chunk.bytesize} bytes..." }
        log(2) { "<- #{chunk.inspect}" }
        @buffer << chunk
        throw(:buffer_full, request) if @buffer.full?
      end
    end

    def capitalized(field)
      field.to_s.split("-").map(&:capitalize).join("-")
    end

    def log(level=@options.debug_level, &msg)
      return unless @options.debug
      return unless @options.debug_level >= level 
      @options.debug << (+"" << msg.call << "\n")
    end
  end
  Channel.register "http/1.1", Channel::HTTP1
end

