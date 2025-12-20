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
      module OptionsMethods
        def option_auth_header_value(value)
          value
        end

        def option_auth_header_type(value)
          value
        end
      end

      module InstanceMethods
        def authorization(token = nil, auth_header_type: nil, &blk)
          with(auth_header_type: auth_header_type, auth_header_value: token || blk)
        end

        def bearer_auth(token = nil, &blk)
          authorization(token, auth_header_type: "Bearer", &blk)
        end
      end

      module RequestMethods
        def initialize(*)
          super

          generate_auth_token
        end

        private

        def generate_auth_token
          return unless (auth_value = @options.auth_header_value)

          auth_value = auth_value.call(self) if auth_value.respond_to?(:call)

          authorize(auth_value)
        end

        def authorize(auth_value)
          if (auth_type = @options.auth_header_type)
            auth_value = "#{auth_type} #{auth_value}"
          end

          @headers.add("authorization", auth_value)
        end
      end
    end
    register_plugin :auth, Auth
  end
end
