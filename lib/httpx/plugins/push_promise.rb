# frozen_string_literal: true

module HTTPX
  module Plugins
    module PushPromise
      PUSH_OPTIONS = { http2_settings: { settings_enable_push: 1 },
                       max_concurrent_requests: 1  }

      module RequestMethods
        def headers=(h)
          @headers = @options.headers_class.new(h)
        end
      end

      module InstanceMethods
        def initialize(opts = {})
          super(PUSH_OPTIONS.merge(opts))
          @promise_headers = {} 
        end

        private

        def on_promise(parser, stream)
          stream.on(:headers) do |h|
            k, _ = h.first
            if k == ":method"
              __on_promise_request(parser, stream, h)
            else
              __on_promise_response(parser, stream, h)
            end
          end
        end

        def __on_promise_request(parser, stream, h)
          log(1, "#{stream.id}: ") do
            h.map { |k, v| "-> HEADER: #{k}: #{v}" }.join("\n")
          end
          headers = @options.headers_class.new(h)
          path = headers[":path"]
          authority = headers[":authority"]
          request = parser.pending.find { |r| r.authority == authority && r.path == path }
          if request
            request.headers = headers
            @promise_headers[stream] = request
          else
            stream.refuse
          end
        end

        def __on_promise_response(parser, stream, h)
          request = @promise_headers.delete(stream)
          return unless request
          parser.__send__(:on_stream_headers, stream, request, h)
          request.transition(:done)
          stream.on(:data, &parser.method(:on_stream_data).curry[stream, request])
          stream.on(:close, &parser.method(:on_stream_close).curry[stream, request])
        end
      end
    end
    register_plugin(:push_promise, PushPromise)
  end
end 
