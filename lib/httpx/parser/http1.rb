# frozen_string_literal: true

module HTTPX
  module Parser
    Error = Class.new(Error)

    class HTTP1
      VERSIONS = %w[1.0 1.1].freeze

      attr_reader :status_code, :http_version, :headers

      def initialize(observer, header_separator: ":")
        @observer = observer
        @state = :idle
        @header_separator = header_separator
        @buffer = "".b
        @headers = {}
      end

      def <<(chunk)
        @buffer << chunk
        parse
      end

      def reset!
        @state = :idle
        @headers.clear
        @content_length = nil
        @_has_trailers = nil
      end

      def upgrade?
        @upgrade
      end

      def upgrade_data
        @buffer
      end

      private

      def parse
        loop do
          state = @state
          case @state
          when :idle
            parse_headline
          when :headers, :trailers
            parse_headers
          when :data
            parse_data
          end
          return if @buffer.empty? || state == @state
        end
      end

      def parse_headline
        idx = @buffer.index("\n")
        return unless idx

        (m = %r{\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)(?:\s+(.*))?}in.match(@buffer)) ||
          raise(Error, "wrong head line format")
        version, code, _ = m.captures
        raise(Error, "unsupported HTTP version (HTTP/#{version})") unless VERSIONS.include?(version)

        @http_version = version.split(".").map(&:to_i)
        @status_code = code.to_i
        raise(Error, "wrong status code (#{@status_code})") unless (100..599).cover?(@status_code)

        # @buffer.slice!(0, idx + 1)
        @buffer = @buffer.byteslice((idx + 1)..-1)
        nextstate(:headers)
      end

      def parse_headers
        headers = @headers
        while (idx = @buffer.index("\n"))
          line = @buffer.slice!(0, idx + 1).sub(/\s+\z/, "")
          if line.empty?
            case @state
            when :headers
              prepare_data(headers)
              @observer.on_headers(headers)
              return unless @state == :headers

              # state might have been reset
              # in the :headers callback
              nextstate(:data)
              headers.clear
            when :trailers
              @observer.on_trailers(headers)
              headers.clear
              nextstate(:complete)
            end
            return
          end
          separator_index = line.index(@header_separator)
          raise Error, "wrong header format" unless separator_index

          key = line[0..separator_index - 1]
          raise Error, "wrong header format" if key.start_with?("\s", "\t")

          key.strip!
          value = line[separator_index + 1..-1]
          value.strip!
          raise Error, "wrong header format" if value.nil?

          (headers[key.downcase] ||= []) << value
        end
      end

      def parse_data
        if @buffer.respond_to?(:each)
          @buffer.each do |chunk|
            @observer.on_data(chunk)
          end
        elsif @content_length
          data = @buffer.byteslice(0, @content_length)
          @buffer = @buffer.byteslice(@content_length..-1) || "".b
          @content_length -= data.bytesize
          @observer.on_data(data)
          data.clear
        else
          @observer.on_data(@buffer)
          @buffer.clear
        end
        return unless no_more_data?

        @buffer = @buffer.to_s
        if @_has_trailers
          nextstate(:trailers)
        else
          nextstate(:complete)
        end
      end

      def prepare_data(headers)
        @upgrade = headers.key?("upgrade")

        @_has_trailers = headers.key?("trailer")

        if (tr_encodings = headers["transfer-encoding"])
          tr_encodings.reverse_each do |tr_encoding|
            tr_encoding.split(/ *, */).each do |encoding|
              case encoding
              when "chunked"
                @buffer = Transcoder::Chunker::Decoder.new(@buffer, @_has_trailers)
              end
            end
          end
        else
          @content_length = headers["content-length"][0].to_i if headers.key?("content-length")
        end
      end

      def no_more_data?
        if @content_length
          @content_length <= 0
        elsif @buffer.respond_to?(:finished?)
          @buffer.finished?
        else
          false
        end
      end

      def nextstate(state)
        @state = state
        case state
        when :headers
          @observer.on_start
        when :complete
          @observer.on_complete
          reset!
          nextstate(:idle) unless @buffer.empty?
        end
      end
    end
  end
end
