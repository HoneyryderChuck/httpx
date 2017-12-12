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
      @responses = []
    end

    def reset
      @parser.reset! 
    end
    alias :close :reset

    def empty?
      # this means that for every request there's an available
      # partial response, so there are no in-flight requests waiting.
      @requests.size == @responses.size
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

    def on_message_begin
      log { "parsing begins" }
    end

    def on_headers_complete(h)
      log { "headers received" }
      headers = @options.headers_class.new(h)
      response = @options.response_class.new(@requests.last, @parser.status_code, headers, @options)
      @responses << response
      log { response.headers.each.map { |f, v| "-> #{f}: #{v}" }.join("\n") }
      request = @requests.last
      # parser can't say if it's parsing GET or HEAD,
      # call the completeness callback manually
      on_message_complete if request.verb == :head
    end

    def on_body(chunk)
      log { "-> #{chunk.inspect}" }
      @responses.last << chunk
    end

    def on_message_complete
      log { "parsing complete" }
      request = @requests.shift
      response = @responses.shift
      reset

      emit(:response, request, response)

      send(@pending.shift) unless @pending.empty?
      return unless response.headers["connection"] == "close"
      log { "connection closed" }
      emit(:close)
    end

    private

    def handle(request)
      catch(:buffer_full) do
        request.headers["connection"] ||= "keep-alive"
        request.transition(:headers)
        join_headers(request) if request.state == :headers
        request.transition(:body)
        join_body(request) if request.state == :body
        request.transition(:done)
      end
    end

    def join_headers(request)
      request.headers["host"] ||= request.authority 
      buffer = +""
      buffer << "#{request.verb.to_s.upcase} #{request.path} HTTP/#{@version.join(".")}" << CRLF
      log { "<- #{buffer.chomp.inspect}" }
      @buffer << buffer
      buffer.clear
      request.headers.each do |field, value|
        buffer << "#{capitalized(field)}: #{value}" << CRLF 
        log { "<- #{buffer.chomp.inspect}" }
        @buffer << buffer
        buffer.clear
      end
      log { "<- " }
      @buffer << CRLF
    end

    def join_body(request)
      return if request.empty?
      while chunk = request.drain_body
        log { "<- #{chunk.inspect}" }
        @buffer << chunk
        throw(:buffer_full, request) if @buffer.full?
      end
    end

    def capitalized(field)
      field.to_s.split("-").map(&:capitalize).join("-")
    end

    def log(&msg)
      return unless $HTTPX_DEBUG
      $stderr << (+"" << msg.call << "\n")
    end
  end
end

