# frozen_string_literal: true

require "tempfile"
require "delegate"

module HTTPX::Plugins
  module Multipart
    CRLF = "\r\n"

    class FilePart < SimpleDelegator
      attr_reader :original_filename, :content_type

      def initialize(filename, content_type)
        @original_filename = filename
        @content_type = content_type
        @file = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
        super(@file)
      end
    end

    TOKEN = %r{[^\s()<>,;:\\"/\[\]?=]+}.freeze
    VALUE = /"(?:\\"|[^"])*"|#{TOKEN}/.freeze
    CONDISP = /Content-Disposition:\s*#{TOKEN}\s*/i.freeze
    BROKEN_QUOTED = /^#{CONDISP}.*;\s*filename="(.*?)"(?:\s*$|\s*;\s*#{TOKEN}=)/i.freeze
    BROKEN_UNQUOTED = /^#{CONDISP}.*;\s*filename=(#{TOKEN})/i.freeze
    MULTIPART_CONTENT_TYPE = /Content-Type: (.*)#{CRLF}/ni.freeze
    MULTIPART_CONTENT_DISPOSITION = /Content-Disposition:.*;\s*name=(#{VALUE})/ni.freeze
    MULTIPART_CONTENT_ID = /Content-ID:\s*([^#{CRLF}]*)/ni.freeze
    # Updated definitions from RFC 2231
    ATTRIBUTE_CHAR = %r{[^ \t\v\n\r)(><@,;:\\"/\[\]?='*%]}.freeze
    ATTRIBUTE = /#{ATTRIBUTE_CHAR}+/.freeze
    SECTION = /\*[0-9]+/.freeze
    REGULAR_PARAMETER_NAME = /#{ATTRIBUTE}#{SECTION}?/.freeze
    REGULAR_PARAMETER = /(#{REGULAR_PARAMETER_NAME})=(#{VALUE})/.freeze
    EXTENDED_OTHER_NAME = /#{ATTRIBUTE}\*[1-9][0-9]*\*/.freeze
    EXTENDED_OTHER_VALUE = /%[0-9a-fA-F]{2}|#{ATTRIBUTE_CHAR}/.freeze
    EXTENDED_OTHER_PARAMETER = /(#{EXTENDED_OTHER_NAME})=(#{EXTENDED_OTHER_VALUE}*)/.freeze
    EXTENDED_INITIAL_NAME = /#{ATTRIBUTE}(?:\*0)?\*/.freeze
    EXTENDED_INITIAL_VALUE = /[a-zA-Z0-9\-]*'[a-zA-Z0-9\-]*'#{EXTENDED_OTHER_VALUE}*/.freeze
    EXTENDED_INITIAL_PARAMETER = /(#{EXTENDED_INITIAL_NAME})=(#{EXTENDED_INITIAL_VALUE})/.freeze
    EXTENDED_PARAMETER = /#{EXTENDED_INITIAL_PARAMETER}|#{EXTENDED_OTHER_PARAMETER}/.freeze
    DISPPARM = /;\s*(?:#{REGULAR_PARAMETER}|#{EXTENDED_PARAMETER})\s*/.freeze
    RFC2183 = /^#{CONDISP}(#{DISPPARM})+$/i.freeze

    class Decoder
      BOUNDARY_RE = /;\s*boundary=([^;]+)/i.freeze
      WINDOW_SIZE = 2 << 14

      def initialize(response)
        @boundary = begin
          m = response.headers["content-type"].to_s[BOUNDARY_RE, 1]
          m && m.strip
        end
        @buffer = "".b
        @parts = {}
        @intermediate_boundary = "--#{@boundary}"
        @state = :idle
      end

      def call(response, _)
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

          head = @buffer.byteslice(0..idx + 4 - 1)

          @buffer = @buffer.byteslice(head.bytesize..-1)

          content_type = head[MULTIPART_CONTENT_TYPE, 1]
          if (name = head[MULTIPART_CONTENT_DISPOSITION, 1])
            name = /\A"(.*)"\Z/ =~ name ? Regexp.last_match(1) : name.dup
            name.gsub!(/\\(.)/, "\\1")
            name
          else
            name = head[MULTIPART_CONTENT_ID, 1]
          end

          filename = get_filename(head)

          name = filename || +"#{content_type || "text/plain"}[]" if name.nil? || name.empty?

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

      def get_filename(head)
        filename = nil
        case head
        when RFC2183
          params = Hash[*head.scan(DISPPARM).flat_map(&:compact)]

          if (filename = params["filename"])
            filename = Regexp.last_match(1) if filename =~ /^"(.*)"$/
          elsif (filename = params["filename*"])
            encoding, _, filename = filename.split("'", 3)
          end
        when BROKEN_QUOTED, BROKEN_UNQUOTED
          filename = Regexp.last_match(1)
        end

        return unless filename

        filename = URI::DEFAULT_PARSER.unescape(filename) if filename.scan(/%.?.?/).all? { |s| /%[0-9a-fA-F]{2}/.match?(s) }

        filename.scrub!

        filename = filename.gsub(/\\(.)/, '\1') unless /\\[^\\"]/.match?(filename)

        filename.force_encoding ::Encoding.find(encoding) if encoding

        filename
      end
    end
  end
end
