# frozen_string_literal: true

module HTTPX
  module Transcoder
    module GRPCEncoding
      class Deflater
        extend Forwardable

        attr_reader :content_type

        def initialize(body, compressed:)
          @content_type = body.content_type
          @body = BodyReader.new(body)
          @compressed = compressed
        end

        def bytesize
          return @body.bytesize if @body.respond_to?(:bytesize)

          Float::INFINITY
        end

        def read(length = nil, outbuf = nil)
          buf = @body.read(length, outbuf)

          return unless buf

          compressed_flag = @compressed ? 1 : 0

          buf = outbuf if outbuf

          buf.prepend([compressed_flag, buf.bytesize].pack("CL>"))
          buf
        end
      end

      class Inflater
        def initialize(response)
          @response = response
          @grpc_encodings = nil
        end

        def call(message, &blk)
          data = "".b

          until message.empty?
            compressed, size = message.unpack("CL>")

            encoded_data = message.byteslice(5..size + 5 - 1)

            if compressed == 1
              grpc_encodings.reverse_each do |encoding|
                decoder = @response.body.class.initialize_inflater_by_encoding(encoding, @response, bytesize: encoded_data.bytesize)
                encoded_data = decoder.call(encoded_data)

                blk.call(encoded_data) if blk

                data << encoded_data
              end
            else
              blk.call(encoded_data) if blk

              data << encoded_data
            end

            message = message.byteslice((size + 5)..-1)
          end

          data
        end

        private

        def grpc_encodings
          @grpc_encodings ||= @response.headers.get("grpc-encoding")
        end
      end

      def self.encode(*args, **kwargs)
        Deflater.new(*args, **kwargs)
      end

      def self.decode(response)
        Inflater.new(response)
      end
    end
  end
end
