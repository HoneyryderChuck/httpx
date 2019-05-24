# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds a shim +authentication+ method to the session, which will fill
    # the HTTP Authorization header.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Authentication#authentication
    #
    module Authentication
      module InstanceMethods
        def authentication(token)
          headers("authorization" => token)
        end
      end
    end
    register_plugin :authentication, Authentication
  end
end
