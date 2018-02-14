# frozen_string_literal: true

module HTTPX
  module Plugins
    module PushPromise
      PUSH_OPTIONS = { http2_settings: { settings_enable_push: 1 },
                       max_concurrent_requests: 1 }.freeze

      module ResponseMethods
        def pushed?
          @__pushed
        end

        def mark_as_pushed!
          @__pushed = true
        end
      end

      module InstanceMethods
        def initialize(opts = {})
          super(PUSH_OPTIONS.merge(opts))
          @promise_headers = {}
        end

        private

        def on_promise(parser, stream)
          stream.on(:promise_headers) do |h|
            __on_promise_request(parser, stream, h)
          end
          stream.on(:headers) do |h|
            __on_promise_response(parser, stream, h)
          end
        end

        def __on_promise_request(parser, stream, h)
          log(1, "#{stream.id}: ") do
            h.map { |k, v| "-> PROMISE HEADER: #{k}: #{v}" }.join("\n")
          end
          headers = @options.headers_class.new(h)
          path = headers[":path"]
          authority = headers[":authority"]
          request = parser.pending.find { |r| r.authority == authority && r.path == path }
          if request
            request.merge_headers(headers)
            @promise_headers[stream] = request
            parser.pending.delete(request)
          else
            stream.refuse
          end
        end

        def __on_promise_response(parser, stream, h)
          request = @promise_headers.delete(stream)
          return unless request
          parser.__send__(:on_stream_headers, stream, request, h)
          request.transition(:done)
          response = request.response
          response.mark_as_pushed!
          stream.on(:data, &parser.method(:on_stream_data).curry[stream, request])
          stream.on(:close, &parser.method(:on_stream_close).curry[stream, request])
        end
      end
    end
    register_plugin(:push_promise, PushPromise)
  end
end
