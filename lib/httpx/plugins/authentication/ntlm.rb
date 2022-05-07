# frozen_string_literal: true

require "base64"
require "ntlm"

module HTTPX
  module Plugins
    module Authentication
      class Ntlm
        def initialize(user, password, domain: nil)
          @user = user
          @password = password
          @domain = domain
        end

        def can_authenticate?(response)
          !response.is_a?(ErrorResponse) && response.status == 401 &&
            response.headers.key?("www-authenticate") &&
            /NTLM .*/.match?(response.headers["www-authenticate"])
        end

        def negotiate
          "NTLM #{NTLM.negotiate(domain: @domain).to_base64}"
        end

        def authenticate(_, response)
          challenge = response.headers["www-authenticate"][/NTLM (.*)/, 1]

          challenge = Base64.decode64(challenge)
          ntlm_challenge = NTLM.authenticate(challenge, @user, @domain, @password).to_base64

          "NTLM #{ntlm_challenge}"
        end
      end
    end
  end
end
