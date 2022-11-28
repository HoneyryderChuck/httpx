# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to implement HTTP Basic Auth (https://tools.ietf.org/html/rfc7617)
    #
    # https://gitlab.com/os85/httpx/wikis/Authentication#basic-authentication
    #
    module BasicAuth
      class << self
        def load_dependencies(_klass)
          require_relative "authentication/basic"
        end

        def configure(klass)
          klass.plugin(:authentication)
        end
      end

      module InstanceMethods
        def basic_auth(user, password)
          authentication(Authentication::Basic.new(user, password).authenticate)
        end
        alias_method :basic_authentication, :basic_auth
      end
    end
    register_plugin :basic_authentication, BasicAuth
  end
end
