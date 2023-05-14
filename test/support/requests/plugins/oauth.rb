# frozen_string_literal: true

module Requests
  module Plugins
    module OAuth
      def test_plugin_oauth_options
        with_oauth_metadata do |server|
          opts = HTTPX.plugin(:oauth).oauth_authentication(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET",
            scope: "all"
          ).instance_variable_get(:@options)

          assert opts.oauth_session.grant_type == "client_credentials"
          assert opts.oauth_session.token_endpoint.to_s == "#{server.origin}/token"
          assert opts.oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert opts.oauth_session.scope == "all"

          opts = HTTPX.plugin(:oauth).oauth_authentication(
            issuer: "https://smthelse",
            token_endpoint_auth_method: "client_secret_post",
            client_id: "CLIENT_ID", client_secret: "SECRET",
            refresh_token: "REFRESH_TOKEN", access_token: "TOKEN",
            scope: %w[foo bar]
          ).instance_variable_get(:@options)
          assert opts.oauth_session.grant_type == "refresh_token"
          assert opts.oauth_session.token_endpoint.to_s == "https://smthelse/token"
          assert opts.oauth_session.token_endpoint_auth_method == "client_secret_post"
          assert opts.oauth_session.scope == %w[foo bar]

          assert_raises(HTTPX::Error) do
            HTTPX.plugin(:oauth).oauth_authentication(
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
              token_endpoint_auth_method: "unsupported"
            )
          end
        end
      end

      def test_plugin_oauth_client_credentials
        with_oauth_metadata do |server|
          session = HTTPX.plugin(:oauth).oauth_authentication(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET", scope: "all"
          )

          client_creds_uri = build_uri("/client-credentials-authed", server.origin)

          response = session.get(client_creds_uri)
          verify_status(response, 401)

          response = session.with_access_token.get(client_creds_uri)
          verify_status(response, 200)
        end
      end

      def test_plugin_oauth_refresh_token
        with_oauth_metadata do |server|
          session = HTTPX.plugin(:oauth).oauth_authentication(
            issuer: server.origin,
            token_endpoint_auth_method: "client_secret_post",
            client_id: "CLIENT_ID", client_secret: "SECRET",
            refresh_token: "REFRESH_TOKEN", access_token: "TOKEN", scope: %w[foo bar]
          )

          refresh_token_uri = build_uri("/refresh-token-authed", server.origin)

          response = session.get(refresh_token_uri)
          verify_status(response, 401)

          response = session.with_access_token.get(refresh_token_uri)
          verify_status(response, 200)
        end
      end

      private

      def with_oauth_metadata(metadata = {})
        start_test_servlet(OAuthProviderServer) do |server|
          server.metadata.merge!(metadata)
          yield server
        end
      end
    end
  end
end
