# frozen_string_literal: true
require "http_parser"

module HTTPX
  class Channel::HTTP1
    include Callbacks

    CRLF = "\r\n"

    def initialize(buffer, version: [1,1], **)
      @parser = HTTP::Parser.new(self)
      @parser.header_value_type = :arrays
      @buffer = buffer
      @version = version
    end

    def reset
      @request = nil
      @response = nil
      @parser.reset! 
    end
    alias :close :reset

    def <<(data)
      @parser << data
    end

    def send(request)
      @request = request
      join_headers(request)
      join_body(request)
    end

    def on_message_begin
      log { "parsing begins" }
    end

    def on_headers_complete(h)
      log { "headers received" }
      @response = Response.new(@parser.status_code, h)
      log { @response.headers.each.map { |f, v| "-> #{f}: #{v}" }.join("\n") }
    end

    def on_body(chunk)
      log { "-> #{chunk.inspect}" }
      @response << chunk
    end

    def on_message_complete
      log { "parsing complete" }
      emit(:response, @request, @response)
      response = @response
      reset
      if response.headers["connection"] == "close"
        throw(:close)
      end
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

