# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # https://gitlab.com/os85/httpx/wikis/OAuth
    #
    module OAuth
      class << self
        def load_dependencies(_klass)
          require_relative "auth/basic"
        end
      end

      SUPPORTED_GRANT_TYPES = %w[client_credentials refresh_token].freeze
      SUPPORTED_AUTH_METHODS = %w[client_secret_basic client_secret_post].freeze

      class OAuthSession
        attr_reader :grant_type, :client_id, :client_secret, :access_token, :refresh_token, :scope, :token_endpoint_form_post

        def initialize(
          issuer:,
          client_id:,
          client_secret:,
          access_token: nil,
          refresh_token: nil,
          scope: nil,
          token_endpoint: nil,
          response_type: nil,
          grant_type: nil,
          token_endpoint_auth_method: nil,
          token_endpoint_form_post: {}
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
          @access_token = access_token
          @refresh_token = refresh_token
          @token_endpoint_auth_method = String(token_endpoint_auth_method) if token_endpoint_auth_method
          @token_endpoint_form_post = token_endpoint_form_post.transform_keys(&:to_s)
          @grant_type = grant_type || (@refresh_token ? "refresh_token" : "client_credentials")

          unless @token_endpoint_auth_method.nil? || SUPPORTED_AUTH_METHODS.include?(@token_endpoint_auth_method)
            raise Error, "#{@token_endpoint_auth_method} is not a supported auth method"
          end

          return if SUPPORTED_GRANT_TYPES.include?(@grant_type)

          raise Error, "#{@grant_type} is not a supported grant type"
        end

        def token_endpoint
          @token_endpoint || "#{@issuer}/token"
        end

        def token_endpoint_auth_method
          @token_endpoint_auth_method || "client_secret_basic"
        end

        def load(http)
          return if @grant_type && @scope

          metadata = http.get("#{@issuer}/.well-known/oauth-authorization-server").raise_for_status.json

          @token_endpoint = metadata["token_endpoint"]
          @scope = metadata["scopes_supported"]
          @grant_type = Array(metadata["grant_types_supported"]).find { |gr| SUPPORTED_GRANT_TYPES.include?(gr) }
          @token_endpoint_auth_method = Array(metadata["token_endpoint_auth_methods_supported"]).find do |am|
            SUPPORTED_AUTH_METHODS.include?(am)
          end
          nil
        end

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
      end

      module OptionsMethods
        private

        def option_oauth_session(value)
          case value
          when Hash
            OAuthSession.new(**value)
          when OAuthSession
            value
          else
            raise TypeError, ":oauth_session must be a #{OAuthSession}"
          end
        end
      end

      module InstanceMethods
        def oauth_auth(**args)
          with(oauth_session: OAuthSession.new(**args))
        end

        def with_access_token
          oauth_session = @options.oauth_session

          oauth_session.load(self)

          grant_type = oauth_session.grant_type

          headers = {}
          form_post = oauth_session.token_endpoint_form_post.merge({ "grant_type" => grant_type, "scope" => Array(oauth_session.scope).join(" ") }).compact

          # auth
          case oauth_session.token_endpoint_auth_method
          when "client_secret_post"
            form_post["client_id"] = oauth_session.client_id
            form_post["client_secret"] = oauth_session.client_secret
          when "client_secret_basic"
            headers["authorization"] = Authentication::Basic.new(oauth_session.client_id, oauth_session.client_secret).authenticate
          end

          case grant_type
          when "client_credentials"
            # do nothing
          when "refresh_token"
            form_post["refresh_token"] = oauth_session.refresh_token
          end

          token_request = build_request("POST", oauth_session.token_endpoint, headers: headers, form: form_post)
          token_request.headers.delete("authorization") unless oauth_session.token_endpoint_auth_method == "client_secret_basic"

          token_response = request(token_request)
          token_response.raise_for_status

          payload = token_response.json

          access_token = payload["access_token"]
          refresh_token = payload["refresh_token"]

          with(oauth_session: oauth_session.merge(access_token: access_token, refresh_token: refresh_token))
        end

        def build_request(*)
          request = super

          return request if request.headers.key?("authorization")

          oauth_session = @options.oauth_session

          return request unless oauth_session && oauth_session.access_token

          request.headers["authorization"] = "Bearer #{oauth_session.access_token}"

          request
        end
      end
    end
    register_plugin :oauth, OAuth
  end
end
