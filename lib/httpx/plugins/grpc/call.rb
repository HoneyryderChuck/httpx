# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    module GRPC
      # Encapsulates call information
      class Call
        def initialize(response, decoder, options)
          @response = response
          @decoder = decoder
          @options = options
        end

        def inspect
          "#GRPC::Call(#{grpc_response})"
        end

        def to_s
          grpc_response.to_s
        end

        def trailing_metadata
          return unless @response.body.closed?

          @response.trailing_metadata
        end

        private

        def grpc_response
          return @grpc_response if defined?(@grpc_response)

          @grpc_response = if @response.respond_to?(:each)
            Enumerator.new do |y|
              @response.each do |message|
                y << @decoder.call(message)
              end
            end
          else
            @decoder.call(@response)
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
