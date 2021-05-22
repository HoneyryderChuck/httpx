# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to implement HTTP Basic Auth (https://tools.ietf.org/html/rfc7617)
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Authentication#basic-authentication
    #
    module BasicAuthentication
      class << self
        def load_dependencies(_klass)
          require "base64"
        end

        def configure(klass)
          klass.plugin(:authentication)
        end
      end

      module InstanceMethods
        def basic_authentication(user, password)
          authentication("Basic #{Base64.strict_encode64("#{user}:#{password}")}")
        end
        alias_method :basic_auth, :basic_authentication
      end
    end
    register_plugin :basic_authentication, BasicAuthentication
  end
end
