# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds a shim +authorization+ method to the session, which will fill
    # the HTTP Authorization header, and another, +bearer_auth+, which fill the "Bearer " prefix
    # in its value.
    #
    # https://gitlab.com/os85/httpx/wikis/Auth#auth
    #
    module Auth
      def self.subplugins
        {
          retries: AuthRetries,
        }
      end

      # adds support for the following options:
      #
      # :auth_header_value :: the token to use as a string, or a callable which returns a string when called.
      # :auth_header_type :: the authentication type to use in the "authorization" header value (i.e. "Bearer", "Digest"...)
      # :auth_header_expires_at :: timestamp at which the auth header will be discarded. should be a callable (like a proc)
      #                            receiving the request as an argument, and should return either a Time object, or an integer (UNIX time).
      # :auth_header_expires_in :: time (in seconds) since the first use of an auth header after which that header will be discarded.
      # :generate_auth_value_on_retry :: callable which returns whether the request should regenerate the auth_header_value
      #                                  when the request is retried (this option will only work if the session also loads the
      #                                  <tt>:retries</tt> plugin).
      module OptionsMethods
        def option_auth_header_value(value)
          value
        end

        def option_auth_header_type(value)
          value
        end

        def option_auth_header_expires_at(value)
          unless value.respond_to?(:call)
            value = Float(value)
            raise TypeError, "`:auth_header_expires_at` must be positive" unless value.positive?
          end

          value
        end

        def option_auth_header_expires_in(value)
          value = Float(value)
          raise TypeError, "`:auth_header_expires_in` must be positive" unless value.positive?

          value
        end

        def option_generate_auth_value_on_retry(value)
          raise TypeError, "`:generate_auth_value_on_retry` must be a callable" unless value.respond_to?(:call)

          value
        end
      end

      module InstanceMethods
        def initialize(*)
          super

          @auth_header_value = @auth_header_expires_at = nil
          @auth_header_value_mtx = Thread::Mutex.new
          @skip_auth_header_value = false
        end

        def authorization(token = nil, auth_header_type: nil, &blk)
          with(auth_header_type: auth_header_type, auth_header_value: token || blk)
        end

        def bearer_auth(token = nil, &blk)
          authorization(token, auth_header_type: "Bearer", &blk)
        end

        def skip_auth_header
          @skip_auth_header_value = true
          yield
        ensure
          @skip_auth_header_value = false
        end

        def reset_auth_header_value!
          @auth_header_value_mtx.synchronize do
            @auth_header_value = @auth_header_expires_at = nil
          end
        end

        private

        def send_request(request, *)
          return super if @skip_auth_header_value || request.authorized?

          auth_header_value = @auth_header_value_mtx.synchronize do
            try_invalidate_auth_header_value

            @auth_header_value ||= begin
              set_auth_header_expires_at(request)
              generate_auth_token
            end
          end

          request.authorize(auth_header_value) if auth_header_value

          super
        end

        def try_invalidate_auth_header_value
          return unless (expires_at = @auth_header_expires_at)

          return if expires_at > Time.now.utc.to_i

          @auth_header_value = @auth_header_expires_at = nil
        end

        def generate_auth_token
          return unless (auth_value = @options.auth_header_value)

          auth_value = auth_value.call(self) if dynamic_auth_token?(auth_value)

          auth_value
        end

        def set_auth_header_expires_at(request)
          @auth_header_expires_at = if (expires_in = request.options.auth_header_expires_in)
            Time.now.to_i + expires_in
          elsif (expires_at = request.options.auth_header_expires_at)
            if expires_at.respond_to?(:call)
              expires_at = expires_at.call(request).to_f
              raise Error, "`:auth_header_expires_at` must be positive" unless expires_at.positive?

              expires_at
            end
          end
        end

        def dynamic_auth_token?(auth_header_value)
          auth_header_value&.respond_to?(:call)
        end
      end

      module RequestMethods
        attr_reader :auth_token_value

        def initialize(*)
          super
          @auth_token_value = @auth_header_value = nil
        end

        def authorized?
          !@auth_token_value.nil?
        end

        def unauthorize!
          return unless (auth_value = @auth_header_value)

          @headers.get("authorization").delete(auth_value)

          @auth_token_value = @auth_header_value = nil
        end

        def authorize(auth_value)
          @auth_header_value = auth_value
          if (auth_type = @options.auth_header_type)
            @auth_header_value = "#{auth_type} #{@auth_header_value}"
          end

          @headers.add("authorization", @auth_header_value)

          @auth_token_value = auth_value
        end
      end

      module AuthRetries
        module InstanceMethods
          private

          def retryable_request?(request, response, options)
            super || auth_error?(response, options)
          end

          def retryable_response?(response, options)
            auth_error?(response, options) || super
          end

          def prepare_to_retry(request, response)
            super

            return unless auth_error?(response, request.options) ||
                          (@options.generate_auth_value_on_retry && @options.generate_auth_value_on_retry.call(response))

            # regenerate token before retry, but only if it's the first request from batch failing.
            # otherwise, it means that the first request already passed here, so this request should
            # use whatever was generated for it.
            @auth_header_value_mtx.synchronize do
              if request.auth_token_value == @auth_header_value
                @auth_header_value = generate_auth_token
                set_auth_header_expires_at(request)
              end
            end

            request.unauthorize!
          end

          def auth_error?(response, options)
            response.is_a?(Response) && response.status == 401 && dynamic_auth_token?(options.auth_header_value)
          end
        end
      end
    end
    register_plugin :auth, Auth
  end
end
