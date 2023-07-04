# frozen_string_literal: true

module HTTPX
  module Transcoder::Multipart
    class Encoder
      attr_reader :bytesize

      def initialize(form)
        @boundary = ("-" * 21) << SecureRandom.hex(21)
        @part_index = 0
        @buffer = "".b

        @form = form
        @parts = to_parts(form)
      end

      def content_type
        "multipart/form-data; boundary=#{@boundary}"
      end

      def read(length = nil, outbuf = nil)
        data   = outbuf.clear.force_encoding(Encoding::BINARY) if outbuf
        data ||= "".b

        read_chunks(data, length)

        data unless length && data.empty?
      end

      def rewind
        form = @form.each_with_object([]) do |(key, val), aux|
          val = val.reopen(val.path, File::RDONLY) if val.is_a?(File) && val.closed?
          val.rewind if val.respond_to?(:rewind)
          aux << [key, val]
        end
        @form = form
        @parts = to_parts(form)
        @part_index = 0
      end

      private

      def to_parts(form)
        @bytesize = 0
        params = form.each_with_object([]) do |(key, val), aux|
          Transcoder.normalize_keys(key, val, MULTIPART_VALUE_COND) do |k, v|
            next if v.nil?

            value, content_type, filename = Part.call(v)

            header = header_part(k, content_type, filename)
            @bytesize += header.size
            aux << header

            @bytesize += value.size
            aux << value

            delimiter = StringIO.new("\r\n")
            @bytesize += delimiter.size
            aux << delimiter
          end
        end
        final_delimiter = StringIO.new("--#{@boundary}--\r\n")
        @bytesize += final_delimiter.size
        params << final_delimiter

        params
      end

      def header_part(key, content_type, filename)
        header = "--#{@boundary}\r\n".b
        header << "Content-Disposition: form-data; name=#{key.inspect}".b
        header << "; filename=#{filename.inspect}" if filename
        header << "\r\nContent-Type: #{content_type}\r\n\r\n"
        StringIO.new(header)
      end

      def read_chunks(buffer, length = nil)
        while @part_index < @parts.size
          chunk = read_from_part(length)

          next unless chunk

          buffer << chunk.force_encoding(Encoding::BINARY)

          next unless length

          length -= chunk.bytesize

          break if length.zero?
        end
      end

      # if there's a current part to read from, tries to read a chunk.
      def read_from_part(max_length = nil)
        part = @parts[@part_index]

        chunk = part.read(max_length, @buffer)

        return chunk if chunk && !chunk.empty?

        part.close if part.respond_to?(:close)

        @part_index += 1

        nil
      end
    end
  end
end
