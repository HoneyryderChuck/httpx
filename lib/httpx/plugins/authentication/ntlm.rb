# frozen_string_literal: true

require "base64"
require "ntlm"

module HTTPX
  module Plugins
    module Authentication
      class Ntlm
        using RegexpExtensions unless Regexp.method_defined?(:match?)

        def initialize(user, password, domain: nil)
          @user = user
          @password = password
          @domain = domain
        end

        def can_authenticate?(authenticate)
          authenticate && /NTLM .*/.match?(authenticate)
        end

        def negotiate
          "NTLM #{NTLM.negotiate(domain: @domain).to_base64}"
        end

        def authenticate(_req, www)
          challenge = www[/NTLM (.*)/, 1]

          challenge = Base64.decode64(challenge)
          ntlm_challenge = NTLM.authenticate(challenge, @user, @domain, @password).to_base64

          "NTLM #{ntlm_challenge}"
        end
      end
    end
  end
end
