# frozen_string_literal: true

module HTTPX
  module Parser
    Error = Class.new(Error)

    class HTTP1
      include Callbacks

      attr_reader :status_code, :http_version, :headers

      def initialize(header_separator: ":")
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
        @buffer.clear
      end

      def upgrade?
        @upgrade
      end

      def upgrade_data
        @buffer
      end

      private

      def parse
        state = @state
        case @state
        when :idle
          parse_headline
        when :headers
          parse_headers
        when :trailers
          parse_headers
        when :data
          parse_data
        end
        parse if !@buffer.empty? && state != @state
      end

      def parse_headline
        idx = @buffer.index("\n")
        return unless idx
        (m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)(?:\s+(.*))?/in.match(@buffer)) ||
          raise(Error, "wrong head line format")
        version, code, _ = m.captures
        unless version == "1.0" || version == "1.1"
          raise(Error, "unsupported HTTP version (HTTP/#{version})")
        end
        @http_version = version.split(".").map(&:to_i)
        @status_code = code.to_i
        unless (100..599).include?(@status_code)
          raise(Error, "wrong status code (#{@status_code})")
        end
        @buffer.slice!(0, idx + 1)
        nextstate(:headers)
      end

      def parse_headers
        headers = @headers
        key = value = nil
        while idx = @buffer.index("\n")
          line = @buffer.slice!(0, idx + 1).sub(/\s+\z/, "")
          if line.empty?
            case @state
            when :headers
              emit(:headers, headers)
              prepare_data(headers)
              headers.clear
              nextstate(:data)
              if @content_length
                nextstate(:complete) if @content_length.zero?
              end
            when :trailers
              emit(:trailers, headers)
              headers.clear
              nextstate(:complete)
            else
              raise Error, "wrong header format"
            end
            return
          end
          separator_index = line.index(@header_separator)
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
            emit(:data, chunk)
          end
        elsif @content_length
          if @buffer.bytesize >= @content_length
            @content_length -= @buffer.bytesize
            emit(:data, @buffer)
            @buffer.clear
          else
            data = @buffer.slice!(0, @content_length)
            @content_length -= data.bytesize
            emit(:data, data)
            data.clear
          end
        else
          emit(:data, @buffer)
          @buffer.clear
        end
        if no_more_data?
          @buffer = @buffer.to_s
          if @_has_trailers
            nextstate(:trailers)
          else
            nextstate(:complete)
          end
        end
      end

      def prepare_data(headers)
        @upgrade = headers.key?("upgrade")

        @_has_trailers = headers.key?("trailer")

        if tr_encodings = headers["transfer-encoding"]
          tr_encodings.reverse_each do |tr_encoding|
            tr_encoding.split(/ *, */).each do |encoding|
              case encoding
              when "chunked"
                @buffer = Transcoder::Chunker::Decoder.new(@buffer)
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
        case state
        when :headers
          emit(:start)
        when :complete
          emit(:complete)
        end
        @state = state
      end
    end
  end
end
