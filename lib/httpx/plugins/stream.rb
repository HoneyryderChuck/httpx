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

          requests = args.first.is_a?(Request) ? args : build_requests(*args, options)

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
        def initialize(*, **)
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

        def each(&block)
          return enum_for(__method__) unless block_given?

          raise Error, "response already streamed" if @response

          @request.stream = self

          begin
            @on_chunk = block

            response.raise_for_status
            response.close
          ensure
            @on_chunk = nil
          end
        end

        def each_line
          return enum_for(__method__) unless block_given?

          line = +""

          each do |chunk|
            line << chunk

            while (idx = line.index("\n"))
              yield line.byteslice(0..idx - 1)

              line = line.byteslice(idx + 1..-1)
            end
          end
        end

        # This is a ghost method. It's to be used ONLY internally, when processing streams
        def on_chunk(chunk)
          raise NoMethodError unless @on_chunk

          @on_chunk.call(chunk.dup)
        end

        # :nocov:
        def inspect
          "#<StreamResponse:#{object_id}>"
        end
        # :nocov:

        def to_s
          response.to_s
        end

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
