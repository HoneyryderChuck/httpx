# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to implement HTTP Digest Auth (https://tools.ietf.org/html/rfc7616)
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Authentication#authentication
    #
    module DigestAuth
      DigestError = Class.new(Error)

      class << self
        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end

        def load_dependencies(*)
          require_relative "authentication/digest"
        end
      end

      module OptionsMethods
        def option_digest(value)
          raise TypeError, ":digest must be a Digest" unless value.is_a?(Authentication::Digest)

          value
        end
      end

      module InstanceMethods
        def digest_authentication(user, password)
          with(digest: Authentication::Digest.new(user, password))
        end

        alias_method :digest_auth, :digest_authentication

        def send_requests(*requests)
          requests.flat_map do |request|
            digest = request.options.digest

            unless digest
              super(request)
              next
            end

            probe_response = wrap { super(request).first }

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

    register_plugin :digest_authentication, DigestAuth
  end
end
