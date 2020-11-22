# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for stream response (text/event-stream).
    #
    module Stream
      module InstanceMethods
        private

        def request(*args, stream: false, **options)
          return super(*args, **options) unless stream

          requests = build_requests(*args, options)

          raise Error, "only 1 response at a time is supported for streaming requests" unless requests.size == 1

          StreamResponse.new(requests.first, self)
        end
      end

      module RequestMethods
        attr_accessor :stream
      end

      module ResponseMethods
        def stream
          @request.stream
        end
      end

      module ResponseBodyMethods
        def initialize(*)
          super
          @stream = @response.stream
        end

        def write(chunk)
          return super unless @stream

          @stream.on_chunk(chunk)
        end

        private

        def transition(*)
          return if @stream

          super
        end
      end

      class StreamResponse
        def initialize(request, session)
          @request = request
          @session = session
          @options = @request.options
        end

        def each_line
          raise Error, "response already streamed" if @response

          Enumerator.new do |yielder|
            @request.stream = self

            @chunk_fiber = Fiber.new do
              response
              :done
            end

            loop do
              chunk = @chunk_fiber.resume

              break if chunk == :done

              yielder << chunk
            end
          end
        end

        # This is a ghost method. It's to be used ONLY internally, when processing streams
        def on_chunk(chunk)
          raise NoMethodError unless @chunk_fiber

          @on_chunk.call(chunk.dup)
        end

        # :nocov:
        def inspect
          "#<StreamResponse:#{object_id} >"
        end
        # :nocov:

        private

        def response
          @response ||= @session.__send__(:send_requests, @request, @options).first
        end

        def respond_to_missing?(*args)
          @options.response_class.respond_to?(*args) || super
        end

        def method_missing(meth, *args, &block)
          if @options.response_class.public_method_defined?(meth)
            response.__send__(meth, *args, &block)
          else
            super
          end
        end
      end
    end
    register_plugin :stream, Stream
  end
end
