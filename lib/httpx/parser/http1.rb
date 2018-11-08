# frozen_string_literal: true

module HTTPX
  module Parser
    Error = Class.new(Error)

    class HTTP1 < Parslet::Parser
      CRLF = "\r\n".b

      attr_reader :status_code, :http_version, :headers

      def initialize
        @state = :idle
        @buffer = String.new("", encoding: Encoding::BINARY)
        @headers = []
      end

      def <<(chunk)
        @buffer << chunk
        parse
      end

      def reset!
        @state = :idle
      end

      private

      def parse
        case @state
        when :idle
          return unless index = @buffer.index(CRLF)
          parse_headline(index)
          @state = :headers
          parse unless @buffer.empty?
        when :headers
          parse_headers
          parse unless @buffer.empty?
        end
      end

      def parse_headline(_index)
        (m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)(?:\s+(.*))?/in.match(@buffer)) ||
          raise(Error, "wrong head line format")
        version, code, _ = m.captures
        @http_version = version.split(".").map(&:to_i)
        @status_code = code.to_i
        @buffer.slice!(0, m.end(0) + 1)
      end

      def parse_headers
        key = value = nil
        while index = @buffer.index(CRLF)
          line = @buffer.slice!(0, index + 2).sub(/\s+\z/, "")
          if line.empty?
            @state = :data
            return
          end
          if (line[0] == "\s") || (line[0] == "\t") && value
            value << " " unless value.empty?
            value << line.strip
          else
            key, value = line.strip.split(/\s*:\s*/, 2)
            @headers << [key, value] if key
            raise Error, "wrong header line format" if value.nil?
          end
        end
      end
    end
  end
end
