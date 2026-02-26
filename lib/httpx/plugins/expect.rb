# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin makes all HTTP/1.1 requests with a body send the "Expect: 100-continue".
    #
    # https://gitlab.com/os85/httpx/wikis/Expect#expect
    #
    module Expect
      EXPECT_TIMEOUT = 2
      NOEXPECT_STORE_MUTEX = Thread::Mutex.new

      class Store
        def initialize
          @store = []
          @mutex = Thread::Mutex.new
        end

        def include?(host)
          @mutex.synchronize { @store.include?(host) }
        end

        def add(host)
          @mutex.synchronize { @store << host }
        end

        def delete(host)
          @mutex.synchronize { @store.delete(host) }
        end
      end

      class << self
        def no_expect_store
          return Ractor.store_if_absent(:httpx_no_expect_store) { Store.new } if Utils.in_ractor?

          @no_expect_store ||= NOEXPECT_STORE_MUTEX.synchronize do
            @no_expect_store || Store.new
          end
        end

        def extra_options(options)
          options.merge(expect_timeout: EXPECT_TIMEOUT)
        end
      end

      # adds support for the following options:
      #
      # :expect_timeout :: time (in seconds) to wait for a 100-expect response,
      #                    before retrying without the Expect header (defaults to <tt>2</tt>).
      # :expect_threshold_size :: min threshold (in bytes) of the request payload to enable the 100-continue negotiation on.
      module OptionsMethods
        private

        def option_expect_timeout(value)
          seconds = Float(value)
          raise TypeError, ":expect_timeout must be positive" unless seconds.positive?

          seconds
        end

        def option_expect_threshold_size(value)
          bytes = Integer(value)
          raise TypeError, ":expect_threshold_size must be positive" unless bytes.positive?

          bytes
        end
      end

      module RequestMethods
        def initialize(*)
          super
          return if @body.empty?

          threshold = @options.expect_threshold_size
          return if threshold && !@body.unbounded_body? && @body.bytesize < threshold

          return if Expect.no_expect_store.include?(origin)

          @headers["expect"] = "100-continue"
        end

        def response=(response)
          if response.is_a?(Response) &&
             response.status == 100 &&
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
            Expect.no_expect_store.delete(origin)
          end
          super
        end
      end

      module ConnectionMethods
        def send_request_to_parser(request)
          super

          return unless request.headers["expect"] == "100-continue"

          expect_timeout = request.options.expect_timeout

          return if expect_timeout.nil? || expect_timeout.infinite?

          set_request_timeout(:expect_timeout, request, expect_timeout, :expect, %i[body response]) do
            # expect timeout expired
            if request.state == :expect && !request.expects?
              Expect.no_expect_store.add(request.origin)
              request.headers.delete("expect")
              consume
            end
          end
        end
      end

      module InstanceMethods
        def fetch_response(request, selector, options)
          response = super

          return unless response

          if response.is_a?(Response) && response.status == 417 && request.headers.key?("expect")
            response.close
            request.headers.delete("expect")
            request.transition(:idle)
            send_request(request, selector, options)
            return
          end

          response
        end
      end
    end
    register_plugin :expect, Expect
  end
end
