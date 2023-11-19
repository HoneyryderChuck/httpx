# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to implement HTTP Basic Auth (https://tools.ietf.org/html/rfc7617)
    #
    # https://gitlab.com/os85/httpx/wikis/Auth#basic-auth
    #
    module BasicAuth
      class << self
        def load_dependencies(_klass)
          require_relative "auth/basic"
        end

        def configure(klass)
          klass.plugin(:auth)
        end
      end

      module InstanceMethods
        def basic_auth(user, password)
          authorization(Authentication::Basic.new(user, password).authenticate)
        end
      end
    end
    register_plugin :basic_auth, BasicAuth
  end
end
