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
        end.new(options).merge(expect_timeout: EXPECT_TIMEOUT)
      end

      module RequestBodyMethods
        def initialize(*)
          super
          return if @body.nil?

          @headers["expect"] = "100-continue"
        end
      end

      module ConnectionMethods
        def send(request)
          request.once(:expects) do
            @timers.after(@options.expect_timeout) do
              if request.state == :expects && !request.expects?
                request.headers.delete("expect")
                handle(request)
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
