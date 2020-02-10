# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for retrying requests when certain errors happen.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Retries
    #
    module Retries
      MAX_RETRIES = 3
      # TODO: pass max_retries in a configure/load block

      IDEMPOTENT_METHODS = %i[get options head put delete].freeze
      RETRYABLE_ERRORS = [IOError,
                          EOFError,
                          Errno::ECONNRESET,
                          Errno::ECONNABORTED,
                          Errno::EPIPE,
                          (OpenSSL::SSL::SSLError if defined?(OpenSSL)),
                          TimeoutError,
                          Parser::Error,
                          Errno::EINVAL,
                          Errno::ETIMEDOUT].freeze

      def self.extra_options(options)
        Class.new(options.class) do
          # number of seconds after which one can retry the request
          def_option(:retry_after) do |num|
            # return early if callable
            return num if num.respond_to?(:call)

            num = Integer(num)
            raise Error, ":retry_after must be positive" unless num.positive?

            num
          end

          def_option(:max_retries) do |num|
            num = Integer(num)
            raise Error, ":max_retries must be positive" unless num.positive?

            num
          end

          def_option(:retry_change_requests)

          def_option(:retry_on) do |callback|
            raise ":retry_on must be called with the response" unless callback.respond_to?(:call) && callback.method(:call).arity == 1

            callback
          end
        end.new(options).merge(max_retries: MAX_RETRIES)
      end

      module InstanceMethods
        def max_retries(n)
          branch(default_options.with_max_retries(n.to_i))
        end

        private

        def fetch_response(request, connections, options)
          response = super

          retry_on = options.retry_on

          if response.is_a?(ErrorResponse) &&
             request.retries.positive? &&
             __repeatable_request?(request, options) &&
             __retryable_error?(response.error) &&
             (!retry_on || retry_on.call(response))
            request.retries -= 1
            log { "failed to get response, #{request.retries} tries to go..." }
            request.transition(:idle)
            connection = find_connection(request, connections, options)
            __retry_request(connection, request, options)
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

        def __retry_request(connection, request, options)
          retry_after = options.retry_after
          unless retry_after
            connection.send(request)
            set_request_timeout(connection, request, options)
            return
          end

          retry_after = retry_after.call(request) if retry_after.respond_to?(:call)
          log { "retrying after #{retry_after} secs..." }
          pool.after(retry_after) do
            log { "retrying!!" }
            connection.send(request)
            set_request_timeout(connection, request, options)
          end
        end
      end

      module RequestMethods
        attr_accessor :retries

        def initialize(*args)
          super
          @retries = @options.max_retries
        end
      end
    end
    register_plugin :retries, Retries
  end
end
