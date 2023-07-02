# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds a shim +authentication+ method to the session, which will fill
    # the HTTP Authorization header.
    #
    # https://gitlab.com/os85/httpx/wikis/Authentication#authentication
    #
    module Authentication
      module InstanceMethods
        def authentication(token)
          with(headers: { "authorization" => token })
        end

        def bearer_auth(token)
          authentication("Bearer #{token}")
        end
      end
    end
    register_plugin :authentication, Authentication
  end
end
