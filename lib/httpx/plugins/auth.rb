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

      module OptionsMethods
        def option_auth_header_value(value)
          value
        end

        def option_auth_header_type(value)
          value
        end

        def option_generate_token_on_retry(value)
          raise TypeError, "`:generate_token_on_retry` must be a callable" unless value.respond_to?(:call)

          value
        end
      end

      module InstanceMethods
        def initialize(*)
          super

          @auth_header_value = nil
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

        private

        def send_request(request, *)
          return super if @skip_auth_header_value

          @auth_header_value ||= generate_auth_token

          request.authorize(@auth_header_value) if @auth_header_value

          super
        end

        def generate_auth_token
          return unless (auth_value = @options.auth_header_value)

          auth_value = auth_value.call(self) if auth_value.respond_to?(:call)

          auth_value
        end
      end

      module RequestMethods
        def authorize(auth_value)
          if (auth_type = @options.auth_header_type)
            auth_value = "#{auth_type} #{auth_value}"
          end

          @headers.add("authorization", auth_value)
        end
      end

      module AuthRetries
        module InstanceMethods
          def prepare_to_retry(request, response)
            super

            return unless @options.generate_token_on_retry && @options.generate_token_on_retry.call(response)

            request.headers.get("authorization").pop
            @auth_header_value = generate_auth_token
          end
        end
      end
    end
    register_plugin :auth, Auth
  end
end
