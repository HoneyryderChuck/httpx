# frozen_string_literal: true

module HTTPX
  module Plugins
    module GRPC
      # Encoding module for GRPC responses
      #
      # Can encode and decode grpc messages.
      module Message
        module_function

        # decodes a unary grpc response
        def unary(response)
          verify_status(response)
          decode(response.to_s, encodings: response.headers.get("grpc-encoding"), encoders: response.encoders)
        end

        # lazy decodes a grpc stream response
        def stream(response)
          return enum_for(__method__, response) unless block_given?

          response.each do |frame|
            yield decode(frame, encodings: response.headers.get("grpc-encoding"), encoders: response.encoders)
          end

          verify_status(response)
        end

        # encodes a single grpc message
        def encode(bytes, deflater:)
          if deflater
            compressed_flag = 1
            bytes = deflater.deflate(StringIO.new(bytes))
          else
            compressed_flag = 0
          end

          "".b << [compressed_flag, bytes.bytesize].pack("CL>") << bytes.to_s
        end

        # decodes a single grpc message
        def decode(message, encodings:, encoders:)
          compressed, size = message.unpack("CL>")
          data = message.byteslice(5..size + 5 - 1)
          if compressed == 1
            encodings.reverse_each do |algo|
              inflater = encoders.registry(algo).inflater(size)
              data = inflater.inflate(data)
              size = data.bytesize
            end
          end
          data
        end

        def cancel(request)
          request.emit(:refuse, :client_cancellation)
        end

        # interprets the grpc call trailing metadata, and raises an
        # exception in case of error code
        def verify_status(response)
          # return standard errors if need be
          response.raise_for_status

          status = Integer(response.headers["grpc-status"])
          message = response.headers["grpc-message"]

          return if status.zero?

          response.close
          raise GRPCError.new(status, message, response.trailing_metadata)
        end
      end
    end
  end
end
