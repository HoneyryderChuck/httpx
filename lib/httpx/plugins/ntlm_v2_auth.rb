# frozen_string_literal: true

module HTTPX
  module Plugins
    # https://gitlab.com/os85/httpx/wikis/Auth#ntlm-auth
    module NtlmV2Auth
      class << self
        def load_dependencies(klass)
          require "rubyntlm"
          klass.plugin(:auth)
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end
      end

      class Authenticator
        def initialize(user, password, domain: nil)
          @user = user
          @password = password
          @domain = domain
        end

        def can_authenticate?(www_authenticate)
          www_authenticate && /NTLM/i.match?(www_authenticate)
        end

        def negotiate
          t1 = Net::NTLM::Message::Type1.new
          t1.domain = @domain if @domain
          "NTLM #{t1.encode64}"
        end

        def authenticate(_request, www_authenticate)
          challenge_b64 = www_authenticate[/NTLM (.+)/i, 1]
          t2 = Net::NTLM::Message.decode64(challenge_b64)
          t3 = t2.response(
            { user: @user, password: @password, domain: @domain },
            ntlmv2: true
          )
          "NTLM #{t3.encode64}"
        end
      end

      module OptionsMethods
        private

        def option_ntlm(value)
          raise TypeError, ":ntlm must be a #{Authenticator}" unless value.is_a?(NtlmV2Auth::Authenticator)

          value
        end
      end

      module InstanceMethods
        def ntlm_auth(user, password, domain = nil)
          with(ntlm: Authenticator.new(user, password, domain: domain))
        end

        private

        def send_requests(*requests)
          requests.flat_map do |request|
            ntlm = request.options.ntlm

            if ntlm
              request.authorize(ntlm.negotiate)
              probe_response = wrap { super(request).first }

              return probe_response unless probe_response.is_a?(Response)

              if probe_response.status == 401 && ntlm.can_authenticate?(probe_response.headers["www-authenticate"])
                request.transition(:idle)
                request.unauthorize!
                request.authorize(ntlm.authenticate(request,
                                                    probe_response.headers["www-authenticate"]).encode("utf-8"))
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

    register_plugin :ntlm_v2_auth, NtlmV2Auth
  end
end
