# frozen_string_literal: true

module HTTPX
  module Plugins
    module GRPC
      # Encapsulates call information
      class Call
        attr_writer :decoder

        def initialize(response)
          @response = response
          @decoder = ->(z) { z }
          @consumed = false
          @grpc_response = nil
        end

        def inspect
          "#GRPC::Call(#{grpc_response})"
        end

        def to_s
          grpc_response.to_s
        end

        def metadata
          response.headers
        end

        def trailing_metadata
          return unless @consumed

          @response.trailing_metadata
        end

        private

        def grpc_response
          @grpc_response ||= if @response.respond_to?(:each)
            Enumerator.new do |y|
              Message.stream(@response).each do |message|
                y << @decoder.call(message)
              end
              @consumed = true
            end
          else
            @consumed = true
            @decoder.call(Message.unary(@response))
          end
        end

        def respond_to_missing?(meth, *args, &blk)
          grpc_response.respond_to?(meth, *args) || super
        end

        def method_missing(meth, *args, &blk)
          return grpc_response.__send__(meth, *args, &blk) if grpc_response.respond_to?(meth)

          super
        end
      end
    end
  end
end
