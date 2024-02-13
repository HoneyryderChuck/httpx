# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when certain errors happen.
    #
    # https://gitlab.com/os85/httpx/wikis/Retries
    #
    module Retries
      MAX_RETRIES = 3
      # TODO: pass max_retries in a configure/load block

      IDEMPOTENT_METHODS = %w[GET OPTIONS HEAD PUT DELETE].freeze
      RETRYABLE_ERRORS = [
        IOError,
        EOFError,
        Errno::ECONNRESET,
        Errno::ECONNABORTED,
        Errno::EPIPE,
        Errno::EINVAL,
        Errno::ETIMEDOUT,
        Parser::Error,
        TLSError,
        TimeoutError,
        ConnectionError,
        Connection::HTTP2::GoawayError,
      ].freeze
      DEFAULT_JITTER = ->(interval) { interval * ((rand + 1) * 0.5) }

      if ENV.key?("HTTPX_NO_JITTER")
        def self.extra_options(options)
          options.merge(max_retries: MAX_RETRIES)
        end
      else
        def self.extra_options(options)
          options.merge(max_retries: MAX_RETRIES, retry_jitter: DEFAULT_JITTER)
        end
      end

      module OptionsMethods
        def option_retry_after(value)
          # return early if callable
          unless value.respond_to?(:call)
            value = Float(value)
            raise TypeError, ":retry_after must be positive" unless value.positive?
          end

          value
        end

        def option_retry_jitter(value)
          # return early if callable
          raise TypeError, ":retry_jitter must be callable" unless value.respond_to?(:call)

          value
        end

        def option_max_retries(value)
          num = Integer(value)
          raise TypeError, ":max_retries must be positive" unless num >= 0

          num
        end

        def option_retry_change_requests(v)
          v
        end

        def option_retry_on(value)
          raise TypeError, ":retry_on must be called with the response" unless value.respond_to?(:call)

          value
        end
      end

      module InstanceMethods
        def max_retries(n)
          with(max_retries: n.to_i)
        end

        private

        def fetch_response(request, connections, options)
          response = super

          if response &&
             request.retries.positive? &&
             __repeatable_request?(request, options) &&
             (
               (
                 response.is_a?(ErrorResponse) && __retryable_error?(response.error)
               ) ||
               (
                 options.retry_on && options.retry_on.call(response)
               )
             )
            __try_partial_retry(request, response)
            log { "failed to get response, #{request.retries} tries to go..." }
            request.retries -= 1
            request.transition(:idle)

            retry_after = options.retry_after
            retry_after = retry_after.call(request, response) if retry_after.respond_to?(:call)

            if retry_after
              # apply jitter
              if (jitter = request.options.retry_jitter)
                retry_after = jitter.call(retry_after)
              end

              retry_start = Utils.now
              log { "retrying after #{retry_after} secs..." }
              pool.after(retry_after) do
                log { "retrying (elapsed time: #{Utils.elapsed_time(retry_start)})!!" }
                send_request(request, connections, options)
              end
            else
              send_request(request, connections, options)
            end

            return
          end
          response
        end

        def __repeatable_request?(request, options)
          IDEMPOTENT_METHODS.include?(request.verb) || options.retry_change_requests
        end

        def __retryable_error?(ex)
          RETRYABLE_ERRORS.any? { |klass| ex.is_a?(klass) }
        end

        def proxy_error?(request, response)
          super && !request.retries.positive?
        end

        #
        # Atttempt to set the request to perform a partial range request.
        # This happens if the peer server accepts byte-range requests, and
        # the last response contains some body payload.
        #
        def __try_partial_retry(request, response)
          response = response.response if response.is_a?(ErrorResponse)

          return unless response

          unless response.headers.key?("accept-ranges") &&
                 response.headers["accept-ranges"] == "bytes" && # there's nothing else supported though...
                 (original_body = response.body)
            response.close if response.respond_to?(:close)
            return
          end

          request.partial_response = response

          size = original_body.bytesize

          request.headers["range"] = "bytes=#{size}-"
        end
      end

      module RequestMethods
        attr_accessor :retries

        attr_writer :partial_response

        def initialize(*args)
          super
          @retries = @options.max_retries
        end

        def response=(response)
          if @partial_response
            if response.is_a?(Response) && response.status == 206
              response.from_partial_response(@partial_response)
            else
              @partial_response.close
            end
            @partial_response = nil
          end

          super
        end
      end

      module ResponseMethods
        def from_partial_response(response)
          @status = response.status
          @headers = response.headers
          @body = response.body
        end
      end
    end
    register_plugin :retries, Retries
  end
end
