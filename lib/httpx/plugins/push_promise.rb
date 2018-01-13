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
          log(1, "#{stream.id}(promise): ") do
            h.map { |k, v| "<- HEADER: #{k}: #{v}" }.join("\n")
          end
          request = @promise_headers.delete(stream)
          return unless request
          _, status = h.shift
          headers = @options.headers_class.new(h)
          response = @options.response_class.new(request, status, "2.0", headers, @options)
          request.response = response
          request.transition(:done)
          parser.streams[request] = stream 
          stream.on(:data) do |data|
            log(1, "#{stream.id}(promise): ") { "<- DATA: #{data.bytesize} bytes..." }
            log(2, "#{stream.id}(promise): ") { "<- #{data.inspect}" }
            request.response << data
          end
          stream.on(:close) do |error|

            if request.expects?
              return handle(request, stream)
            end
            response = request.response || ErrorResponse.new(error, retries)
            on_response(request, response)
            log(2, "#{stream.id}(promise): ") { "closing stream" }


            parser.streams.delete(request)
          end
        end
      end
    end
    register_plugin(:push_promise, PushPromise)
  end
end 
