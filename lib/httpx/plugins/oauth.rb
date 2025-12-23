# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for managing an OAuth Session associated with the given session.
    #
    # The scope of OAuth support is limited to the `client_crendentials` and `refresh_token` grants.
    #
    # https://gitlab.com/os85/httpx/wikis/OAuth
    #
    module OAuth
      class << self
        def load_dependencies(klass)
          require_relative "auth/basic"
          klass.plugin(:auth)
        end

        def subplugins
          {
            retries: OAuthRetries,
          }
        end

        def extra_options(options)
          options.merge(auth_header_type: "Bearer")
        end
      end

      SUPPORTED_GRANT_TYPES = %w[client_credentials refresh_token].freeze
      SUPPORTED_AUTH_METHODS = %w[client_secret_basic client_secret_post].freeze

      # Implements the bulk of functionality and maintains the state associated with the
      # management of the the lifecycle of an OAuth session.
      class OAuthSession
        attr_reader :access_token, :refresh_token

        def initialize(
          issuer:,
          client_id:,
          client_secret:,
          access_token: nil,
          refresh_token: nil,
          scope: nil,
          audience: nil,
          token_endpoint: nil,
          response_type: nil,
          grant_type: nil,
          token_endpoint_auth_method: nil
        )
          @issuer = URI(issuer)
          @client_id = client_id
          @client_secret = client_secret
          @token_endpoint = URI(token_endpoint) if token_endpoint
          @response_type = response_type
          @scope = case scope
                   when String
                     scope.split
                   when Array
                     scope
          end
          @audience = audience
          @access_token = access_token
          @refresh_token = refresh_token
          @token_endpoint_auth_method = String(token_endpoint_auth_method) if token_endpoint_auth_method
          @grant_type = grant_type || (@refresh_token ? "refresh_token" : "client_credentials")
          @access_token = access_token
          @refresh_token = refresh_token

          unless @token_endpoint_auth_method.nil? || SUPPORTED_AUTH_METHODS.include?(@token_endpoint_auth_method)
            raise Error, "#{@token_endpoint_auth_method} is not a supported auth method"
          end

          return if SUPPORTED_GRANT_TYPES.include?(@grant_type)

          raise Error, "#{@grant_type} is not a supported grant type"
        end

        # returns the URL where to request access and refresh tokens from.
        def token_endpoint
          @token_endpoint || "#{@issuer}/token"
        end

        # returns the oauth-documented authorization method to use when requesting a token.
        def token_endpoint_auth_method
          @token_endpoint_auth_method || "client_secret_basic"
        end

        def reset!
          @access_token = nil
        end

        # when not available, it uses the +http+ object to request new access and refresh tokens.
        def fetch_access_token(http)
          return access_token if access_token

          load(http)

          # always prefer refresh token grant if a refresh token is available
          grant_type = @refresh_token ? "refresh_token" : @grant_type

          headers = {} # : Hash[String ,String]
          form_post = {
            "grant_type" => @grant_type,
            "scope" => Array(@scope).join(" "),
            "audience" => @audience,
          }.compact

          # auth
          case token_endpoint_auth_method
          when "client_secret_post"
            form_post["client_id"] = @client_id
            form_post["client_secret"] = @client_secret
          when "client_secret_basic"
            headers["authorization"] = Authentication::Basic.new(@client_id, @client_secret).authenticate
          end

          case grant_type
          when "client_credentials"
            # do nothing
          when "refresh_token"
            raise Error, "cannot use the `\"refresh_token\"` grant type without a refresh token" unless refresh_token

            form_post["refresh_token"] = refresh_token
          end

          # POST /token
          token_request = http.build_request("POST", token_endpoint, headers: headers, form: form_post)

          token_request.headers.delete("authorization") unless token_endpoint_auth_method == "client_secret_basic"

          token_response = http.skip_auth_header { http.request(token_request) }

          begin
            token_response.raise_for_status
          rescue HTTPError => e
            @refresh_token = nil if e.response.status == 401 && (grant_type == "refresh_token")
            raise e
          end

          payload = token_response.json

          @refresh_token = payload["refresh_token"] || @refresh_token
          @access_token = payload["access_token"]
        end

        # TODO: remove this after deprecating the `:oauth_session` option
        def merge(other)
          obj = dup

          case other
          when OAuthSession
            other.instance_variables.each do |ivar|
              val = other.instance_variable_get(ivar)
              next unless val

              obj.instance_variable_set(ivar, val)
            end
          when Hash
            other.each do |k, v|
              obj.instance_variable_set(:"@#{k}", v) if obj.instance_variable_defined?(:"@#{k}")
            end
          end
          obj
        end

        private

        # uses +http+ to fetch for the oauth server metadata.
        def load(http)
          return if @grant_type && @scope

          metadata = http.skip_auth_header { http.get("#{@issuer}/.well-known/oauth-authorization-server").raise_for_status.json }

          @token_endpoint = metadata["token_endpoint"]
          @scope = metadata["scopes_supported"]
          @grant_type = Array(metadata["grant_types_supported"]).find { |gr| SUPPORTED_GRANT_TYPES.include?(gr) }
          @token_endpoint_auth_method = Array(metadata["token_endpoint_auth_methods_supported"]).find do |am|
            SUPPORTED_AUTH_METHODS.include?(am)
          end
          nil
        end
      end

      module OptionsMethods
        private

        def option_oauth_session(value)
          warn "DEPRECATION WARNING: option `:oauth_session` is deprecated. " \
               "Use `:oauth_options` instead."

          case value
          when Hash
            OAuthSession.new(**value)
          when OAuthSession
            value
          else
            raise TypeError, ":oauth_session must be a #{OAuthSession}"
          end
        end

        def option_oauth_options(value)
          value = Hash[value] unless value.is_a?(Hash)
          value
        end
      end

      module InstanceMethods
        attr_reader :oauth_session
        protected :oauth_session

        def initialize(*)
          super

          @oauth_session = if @options.oauth_options
            OAuthSession.new(**@options.oauth_options)
          elsif @options.oauth_session
            @oauth_session = @options.oauth_session.dup
          end
        end

        def initialize_dup(other)
          super
          @oauth_session = other.instance_variable_get(:@oauth_session).dup
        end

        def oauth_auth(**args)
          warn "DEPRECATION WARNING: `#{__method__}` is deprecated. " \
               "Use `with(oauth_options: options)` instead."

          with(oauth_options: args)
        end

        # TODO: deprecate
        def with_access_token
          warn "DEPRECATION WARNING: `#{__method__}` is deprecated. " \
               "The session will automatically handle token lifecycles for you."

          other_session = dup # : instance
          oauth_session = other_session.oauth_session
          oauth_session.fetch_access_token(other_session)
          other_session
        end

        private

        def generate_auth_token
          return unless @oauth_session

          @oauth_session.fetch_access_token(self)
        end
      end

      module OAuthRetries
        class << self
          def extra_options(options)
            options.merge(retry_on: method(:response_oauth_error), generate_token_on_retry: method(:response_oauth_error))
          end

          def response_oauth_error(res)
            res.is_a?(Response) && res.status == 401
          end
        end

        module InstanceMethods
          def prepare_to_retry(_request, response)
            return super unless @oauth_session && @options.generate_token_on_retry && @options.generate_token_on_retry.call(response)

            @oauth_session.reset!

            super
          end
        end
      end
    end
    register_plugin :oauth, OAuth
  end
end
