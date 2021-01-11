# frozen_string_literal: true

module HTTPX::Plugins
  module Multipart
    class Encoder
      def initialize(form)
        @boundary = ("-" * 21) << SecureRandom.hex(21)
        @part_index = 0
        @buffer = "".b

        @parts = to_parts(form)
      end

      def content_type
        "multipart/form-data; boundary=#{@boundary}"
      end

      def bytesize
        @parts.map(&:size).sum
      end

      def read(length = nil, outbuf = nil)
        data   = outbuf.clear.force_encoding(Encoding::BINARY) if outbuf
        data ||= "".b

        read_chunks(data, length)

        data unless length && data.empty?
      end

      private

      def to_parts(form)
        params = form.each_with_object([]) do |(key, val), aux|
          Multipart.normalize_keys(key, val) do |k, v|
            value, content_type, filename = Part.call(v)
            aux << header_part(k, content_type, filename)
            aux << value
            aux << StringIO.new("\r\n")
          end
        end
        params << StringIO.new("--#{@boundary}--\r\n")
        params
      end

      def header_part(key, content_type, filename)
        header = "--#{@boundary}\r\n".b
        header << "Content-Disposition: form-data; name=#{key}".b
        header << "; filename=#{filename}" if filename
        header << "\r\nContent-Type: #{content_type}\r\n\r\n"
        StringIO.new(header)
      end

      def read_chunks(buffer, length = nil)
        while (chunk = read_from_part(length))
          buffer << chunk.force_encoding(Encoding::BINARY)

          next unless length

          length -= chunk.bytesize

          break if length.zero?
        end
      end

      # if there's a current part to read from, tries to read a chunk.
      def read_from_part(max_length = nil)
        return unless @part_index < @parts.size

        part = @parts[@part_index]

        chunk = part.read(max_length, @buffer)

        return chunk if chunk && !chunk.empty?

        @part_index += 1

        nil
      end
    end
  end
end
