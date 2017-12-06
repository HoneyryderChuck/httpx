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
      @requests.empty?
    end

    def <<(data)
      @parser << data
    end

    def send(request, **)
      if @requests.size >= @max_concurrent_requests
        @pending << request
        return
      end
      @requests << request
      join_headers(request)
      join_body(request)
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
      response =  Response.new(@parser.status_code, h)
      @responses << response
      log { response.headers.each.map { |f, v| "-> #{f}: #{v}" }.join("\n") }
    end

    def on_body(chunk)
      log { "-> #{chunk.inspect}" }
      @responses.last << chunk
    end

    def on_message_complete
      log { "parsing complete" }
      request = @requests.shift
      response = @responses.shift
      emit(:response, request, response)
      reset
      emit(:close) if response.headers["connection"] == "close"

      send(@pending.shift) unless @pending.empty?
    end

    private

    def join_headers(request)
      request.headers["host"] ||= request.authority 
      buffer = +""
      buffer << "#{request.verb.to_s.upcase} #{request.path} HTTP/#{@version.join(".")}" << CRLF
      log { "<- #{buffer.inspect}" }
      @buffer << buffer
      buffer.clear
      request.headers.each do |field, value|
        buffer << "#{capitalized(field)}: #{value}" << CRLF 
        log { "<- #{buffer.inspect}" }
        @buffer << buffer
        buffer.clear
      end
      @buffer << CRLF
    end

    def join_body(request)
      return unless request.body
      request.body.each do |chunk|
        log { "<- #{chunk}" }
        @buffer << chunk
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

