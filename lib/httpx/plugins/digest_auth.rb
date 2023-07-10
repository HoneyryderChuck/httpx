# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to implement HTTP Digest Auth (https://tools.ietf.org/html/rfc7616)
    #
    # https://gitlab.com/os85/httpx/wikis/Authorization#digest-auth
    #
    module DigestAuth
      DigestError = Class.new(Error)

      class << self
        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end

        def load_dependencies(*)
          require_relative "auth/digest"
        end
      end

      module OptionsMethods
        def option_digest(value)
          raise TypeError, ":digest must be a #{Authentication::Digest}" unless value.is_a?(Authentication::Digest)

          value
        end
      end

      module InstanceMethods
        def digest_auth(user, password)
          with(digest: Authentication::Digest.new(user, password))
        end

        private

        def send_requests(*requests)
          requests.flat_map do |request|
            digest = request.options.digest

            next super(request) unless digest

            probe_response = wrap { super(request).first }

            return probe_response unless probe_response.is_a?(Response)

            if probe_response.status == 401 && digest.can_authenticate?(probe_response.headers["www-authenticate"])
              request.transition(:idle)
              request.headers["authorization"] = digest.authenticate(request, probe_response.headers["www-authenticate"])
              super(request)
            else
              probe_response
            end
          end
        end
      end
    end

    register_plugin :digest_auth, DigestAuth
  end
end
