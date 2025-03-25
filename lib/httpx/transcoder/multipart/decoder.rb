# frozen_string_literal: true

require "tempfile"
require "delegate"

module HTTPX
  module Transcoder
    module Multipart
      class FilePart < SimpleDelegator
        attr_reader :original_filename, :content_type

        def initialize(filename, content_type)
          @original_filename = filename
          @content_type = content_type
          @current = nil
          @file = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
          super(@file)
        end
      end

      class Decoder
        include HTTPX::Utils

        CRLF = "\r\n"
        BOUNDARY_RE = /;\s*boundary=([^;]+)/i.freeze
        MULTIPART_CONTENT_TYPE = /Content-Type: (.*)#{CRLF}/ni.freeze
        MULTIPART_CONTENT_DISPOSITION = /Content-Disposition:.*;\s*name=(#{VALUE})/ni.freeze
        MULTIPART_CONTENT_ID = /Content-ID:\s*([^#{CRLF}]*)/ni.freeze
        WINDOW_SIZE = 2 << 14

        def initialize(response)
          @boundary = begin
            m = response.headers["content-type"].to_s[BOUNDARY_RE, 1]
            raise Error, "no boundary declared in content-type header" unless m

            m.strip
          end
          @buffer = "".b
          @parts = {}
          @intermediate_boundary = "--#{@boundary}"
          @state = :idle
        end

        def call(response, *)
          response.body.each do |chunk|
            @buffer << chunk

            parse
          end

          raise Error, "invalid or unsupported multipart format" unless @buffer.empty?

          @parts
        end

        private

        def parse
          case @state
          when :idle
            raise Error, "payload does not start with boundary" unless @buffer.start_with?("#{@intermediate_boundary}#{CRLF}")

            @buffer = @buffer.byteslice(@intermediate_boundary.bytesize + 2..-1)

            @state = :part_header
          when :part_header
            idx = @buffer.index("#{CRLF}#{CRLF}")

            # raise Error, "couldn't parse part headers" unless idx
            return unless idx

            # @type var head: String
            head = @buffer.byteslice(0..idx + 4 - 1)

            @buffer = @buffer.byteslice(head.bytesize..-1)

            content_type = head[MULTIPART_CONTENT_TYPE, 1] || "text/plain"
            if (name = head[MULTIPART_CONTENT_DISPOSITION, 1])
              name = /\A"(.*)"\Z/ =~ name ? Regexp.last_match(1) : name.dup
              name.gsub!(/\\(.)/, "\\1")
              name
            else
              name = head[MULTIPART_CONTENT_ID, 1]
            end

            filename = HTTPX::Utils.get_filename(head)

            name = filename || +"#{content_type}[]" if name.nil? || name.empty?

            @current = name

            @parts[name] = if filename
              FilePart.new(filename, content_type)
            else
              "".b
            end

            @state = :part_body
          when :part_body
            part = @parts[@current]

            body_separator = if part.is_a?(FilePart)
              "#{CRLF}#{CRLF}"
            else
              CRLF
            end
            idx = @buffer.index(body_separator)

            if idx
              payload = @buffer.byteslice(0..idx - 1)
              @buffer = @buffer.byteslice(idx + body_separator.bytesize..-1)
              part << payload
              part.rewind if part.respond_to?(:rewind)
              @state = :parse_boundary
            else
              part << @buffer
              @buffer.clear
            end
          when :parse_boundary
            raise Error, "payload does not start with boundary" unless @buffer.start_with?(@intermediate_boundary)

            @buffer = @buffer.byteslice(@intermediate_boundary.bytesize..-1)

            if @buffer == "--"
              @buffer.clear
              @state = :done
              return
            elsif @buffer.start_with?(CRLF)
              @buffer = @buffer.byteslice(2..-1)
              @state = :part_header
            else
              return
            end
          when :done
            raise Error, "parsing should have been over by now"
          end until @buffer.empty?
        end
      end
    end
  end
end
