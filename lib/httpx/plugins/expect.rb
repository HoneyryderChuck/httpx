# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin makes all HTTP/1.1 requests with a body send the "Expect: 100-continue".
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Expect#expect
    #
    module Expect
      EXPECT_TIMEOUT = 2

      def self.extra_options(options)
        Class.new(options.class) do
          def_option(:expect_timeout) do |seconds|
            seconds = Integer(seconds)
            raise Error, ":expect_timeout must be positive" unless seconds.positive?

            seconds
          end

          def_option(:expect_threshold_size) do |bytes|
            bytes = Integer(bytes)
            raise Error, ":expect_threshold_size must be positive" unless bytes.positive?

            bytes
          end
        end.new(options).merge(expect_timeout: EXPECT_TIMEOUT)
      end

      module RequestMethods
        def response=(response)
          if response && response.status == 100 &&
             !@headers.key?("expect") &&
             (@state == :body || @state == :done)

            # if we're past this point, this means that we just received a 100-Continue response,
            # but the request doesn't have the expect flag, and is already flushing (or flushed) the body.
            #
            # this means that expect was deactivated for this request too soon, i.e. response took longer.
            #
            # so we have to reactivate it again.
            @headers["expect"] = "100-continue"
            @informational_status = 100
          end
          super
        end
      end

      module RequestBodyMethods
        def initialize(*, options)
          super
          return if @body.nil?

          threshold = options.expect_threshold_size
          return if threshold && !unbounded_body? && @body.bytesize < threshold

          @headers["expect"] = "100-continue"
        end
      end

      module ConnectionMethods
        def send(request)
          request.once(:expect) do
            @timers.after(@options.expect_timeout) do
              if request.state == :expect && !request.expects?
                request.headers.delete("expect")
                consume
              end
            end
          end
          super
        end
      end

      module InstanceMethods
        def fetch_response(request, connections, options)
          response = @responses.delete(request)
          return unless response

          if response.status == 417 && request.headers.key?("expect")
            response.close
            request.headers.delete("expect")
            request.transition(:idle)
            connection = find_connection(request, connections, options)
            connection.send(request)
            return
          end

          response
        end
      end
    end
    register_plugin :expect, Expect
  end
end
