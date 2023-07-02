# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds a shim +authorization+ method to the session, which will fill
    # the HTTP Authorization header, and another, +bearer_auth+, which fill the "Bearer " prefix
    # in its value.
    #
    # https://gitlab.com/os85/httpx/wikis/Auth#authorization
    #
    module Auth
      module InstanceMethods
        def authorization(token)
          with(headers: { "authorization" => token })
        end

        def bearer_auth(token)
          authorization("Bearer #{token}")
        end
      end
    end
    register_plugin :auth, Auth
  end
end
