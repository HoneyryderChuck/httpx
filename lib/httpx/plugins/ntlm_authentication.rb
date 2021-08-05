# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Authentication#ntlm-authentication
    #
    module NTLMAuthentication
      NTLMParams = Struct.new(:user, :domain, :password)

      class << self
        def load_dependencies(_klass)
          require "base64"
          require "ntlm"
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end
      end

      module OptionsMethods
        def option_ntlm(value)
          raise TypeError, ":ntlm must be a #{NTLMParams}" unless value.is_a?(NTLMParams)

          value
        end
      end

      module InstanceMethods
        def ntlm_authentication(user, password, domain = nil)
          with(ntlm: NTLMParams.new(user, domain, password))
        end

        alias_method :ntlm_auth, :ntlm_authentication

        def send_requests(*requests)
          requests.flat_map do |request|
            ntlm = request.options.ntlm

            if ntlm
              request.headers["authorization"] = "NTLM #{NTLM.negotiate(domain: ntlm.domain).to_base64}"
              probe_response = wrap { super(request).first }

              if !probe_response.is_a?(ErrorResponse) && probe_response.status == 401 &&
                 probe_response.headers.key?("www-authenticate") &&
                 (challenge = probe_response.headers["www-authenticate"][/NTLM (.*)/, 1])

                challenge = Base64.decode64(challenge)
                ntlm_challenge = NTLM.authenticate(challenge, ntlm.user, ntlm.domain, ntlm.password).to_base64

                request.transition(:idle)

                request.headers["authorization"] = "NTLM #{ntlm_challenge}"
                super(request)
              else
                probe_response
              end
            else
              super(request)
            end
          end
        end
      end
    end
    register_plugin :ntlm_authentication, NTLMAuthentication
  end
end
