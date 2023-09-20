# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # https://gitlab.com/os85/httpx/wikis/Authorization#ntlm-auth
    #
    module NTLMAuth
      class << self
        def load_dependencies(_klass)
          require_relative "auth/ntlm"
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end
      end

      module OptionsMethods
        def option_ntlm(value)
          raise TypeError, ":ntlm must be a #{Authentication::Ntlm}" unless value.is_a?(Authentication::Ntlm)

          value
        end
      end

      module InstanceMethods
        def ntlm_auth(user, password, domain = nil)
          with(ntlm: Authentication::Ntlm.new(user, password, domain: domain))
        end

        private

        def send_requests(*requests)
          requests.flat_map do |request|
            ntlm = request.options.ntlm

            if ntlm
              request.headers["authorization"] = ntlm.negotiate
              probe_response = wrap { super(request).first }

              return probe_response unless probe_response.is_a?(Response)

              if probe_response.status == 401 && ntlm.can_authenticate?(probe_response.headers["www-authenticate"])
                request.transition(:idle)
                request.headers["authorization"] = ntlm.authenticate(request, probe_response.headers["www-authenticate"])
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
    register_plugin :ntlm_auth, NTLMAuth
  end
end
