# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when errors happen.
    #
    # It has a default max number of retries (see *MAX_RETRIES* and the *max_retries* option),
    # after which it will return the last response, error or not. It will **not** raise an exception.
    #
    # It does not retry which are not considered idempotent (see *retry_change_requests* to override).
    #
    # https://gitlab.com/os85/httpx/wikis/Retries
    #
    module Retries
      MAX_RETRIES = 3
      # TODO: pass max_retries in a configure/load block

      IDEMPOTENT_METHODS = %w[GET OPTIONS HEAD PUT DELETE].freeze

      # subset of retryable errors which are safe to retry when reconnecting
      RECONNECTABLE_ERRORS = [
        IOError,
        EOFError,
        Errno::ECONNRESET,
        Errno::ECONNABORTED,
        Errno::EPIPE,
        Errno::EINVAL,
        Errno::ETIMEDOUT,
        ConnectionError,
        TLSError,
        Connection::HTTP2::Error,
      ].freeze

      RETRYABLE_ERRORS = (RECONNECTABLE_ERRORS + [
        Parser::Error,
        TimeoutError,
      ]).freeze

      DEFAULT_JITTER = ->(interval) { interval * ((rand + 1) * 0.5) }.freeze

      # list of supported backoff algorithms
      BACKOFF_ALGORITHMS = %i[exponential_backoff polynomial_backoff].freeze

      class << self
        if ENV.key?("HTTPX_NO_JITTER")
          def extra_options(options)
            options.merge(max_retries: MAX_RETRIES)
          end
        else
          def extra_options(options)
            options.merge(max_retries: MAX_RETRIES, retry_jitter: DEFAULT_JITTER)
          end
        end

        # returns the time to wait before resending +request+ as per the polynomial backoff retry strategy.
        def retry_after_polynomial_backoff(request, _)
          offset = request.options.max_retries - request.retries
          2 * (offset - 1)
        end

        # returns the time to wait before resending +request+ as per the exponential backoff retry strategy.
        def retry_after_exponential_backoff(request, _)
          offset = request.options.max_retries - request.retries
          (offset - 1) * 2
        end
      end

      # adds support for the following options:
      #
      # :max_retries :: max number of times a request will be retried (defaults to <tt>3</tt>).
      # :retry_change_requests :: whether idempotent requests are retried (defaults to <tt>false</tt>).
      # :retry_after:: seconds after which a request is retried; can also be a callable object (i.e. <tt>->(req, res) { ... } </tt>)
      #                or the name of a supported backoff algorithm (i.e. <tt>:exponential_backoff</tt>).
      # :retry_jitter :: number of seconds applied to *:retry_after* (must be a callable, i.e. <tt>->(retry_after) { ... } </tt>).
      # :retry_on :: callable which alternatively defines a different rule for when a response is to be retried
      #              (i.e. <tt>->(res) { ... }</tt>).
      module OptionsMethods
        private

        def option_retry_after(value)
          if value.respond_to?(:call)
            value1 = value
            value1 = value1.method(:call) unless value1.respond_to?(:arity)

            # allow ->(*) arity as well, which is < 0
            raise TypeError, "`:retry_after` proc has invalid number of parameters" unless value1.arity.negative? || value1.arity.between?(
              1, 2
            )

          else
            case value
            when Symbol
              raise TypeError, "`retry_after`: `#{value}` is not a supported backoff algorithm" unless BACKOFF_ALGORITHMS.include?(value)

              value = Retries.method(:"retry_after_#{value}")

            else
              value = Float(value)
              raise TypeError, "`:retry_after` must be positive" unless value.positive?
            end
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
        # returns a `:retries` plugin enabled session with +n+ maximum retries per request setting.
        def max_retries(n)
          with(max_retries: n)
        end

        private

        def fetch_response(request, selector, options)
          response = super

          if response &&
             request.retries.positive? &&
             retryable_request?(request, response, options) &&
             retryable_response?(response, options)
            try_partial_retry(request, response)
            log { "failed to get response, #{request.retries} tries to go..." }
            prepare_to_retry(request, response)

            retry_after = options.retry_after
            retry_after = retry_after.call(request, response) if retry_after.respond_to?(:call)

            if retry_after
              # apply jitter
              if (jitter = request.options.retry_jitter)
                retry_after = jitter.call(retry_after)
              end

              retry_start = Utils.now
              log { "retrying after #{retry_after} secs..." }
              selector.after(retry_after) do
                if (response = request.response)
                  response.finish!
                  # request has terminated abruptly meanwhile
                  request.emit(:response, response)
                else
                  log { "retrying (elapsed time: #{Utils.elapsed_time(retry_start)})!!" }
                  send_request(request, selector, options)
                end
              end
            else
              send_request(request, selector, options)
            end

            return
          end
          response
        end

        # returns whether +request+ can be retried.
        def retryable_request?(request, _, options)
          IDEMPOTENT_METHODS.include?(request.verb) || options.retry_change_requests
        end

        def retryable_response?(response, options)
          (response.is_a?(ErrorResponse) && retryable_error?(response.error, options)) || options.retry_on&.call(response)
        end

        # returns whether the +ex+ exception happend for a retriable request.
        def retryable_error?(ex, _)
          RETRYABLE_ERRORS.any? { |klass| ex.is_a?(klass) }
        end

        def proxy_error?(request, response, _)
          super && !request.retries.positive?
        end

        def prepare_to_retry(request, _response)
          request.retries -= 1 unless request.ping? # do not exhaust retries on connection liveness probes
          request.transition(:idle)
        end

        #
        # Attempt to set the request to perform a partial range request.
        # This happens if the peer server accepts byte-range requests, and
        # the last response contains some body payload.
        #
        def try_partial_retry(request, response)
          response = response.response if response.is_a?(ErrorResponse)

          return unless response

          unless response.headers.key?("accept-ranges") &&
                 response.headers["accept-ranges"] == "bytes" && # there's nothing else supported though...
                 (original_body = response.body)
            response.body.close
            return
          end

          request.partial_response = response

          size = original_body.bytesize

          request.headers["range"] = "bytes=#{size}-"
        end
      end

      module RequestMethods
        # number of retries left.
        attr_accessor :retries

        # a response partially received before.
        attr_writer :partial_response

        # initializes the request instance, sets the number of retries for the request.
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
