# frozen_string_literal: true

module Requests
  module Plugins
    module OAuth
      def test_plugin_oauth_oauth_session
        with_oauth_metadata do |server|
          # from options
          oauth_session = HTTPX.plugin(:oauth).with_oauth_options(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET",
            scope: "all"
          ).send(:oauth_session)

          assert oauth_session.token_endpoint == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[all]
          assert oauth_session.instance_variable_get(:@audience).nil?

          # with audience
          oauth_session = HTTPX.plugin(:oauth).with_oauth_options(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET",
            scope: "all",
            audience: "audience"
          ).send(:oauth_session)

          assert oauth_session.token_endpoint.to_s == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[all]
          assert oauth_session.instance_variable_get(:@audience) == "audience"

          # from options, pointing to refresh
          oauth_session = HTTPX.plugin(:oauth).with_oauth_options(
            issuer: "https://smthelse",
            token_endpoint_auth_method: "client_secret_post",
            client_id: "CLIENT_ID", client_secret: "SECRET",
            refresh_token: "REFRESH_TOKEN", access_token: "TOKEN",
            scope: %w[foo bar]
          ).send(:oauth_session)
          assert oauth_session.token_endpoint.to_s == "https://smthelse/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_post"
          assert oauth_session.instance_variable_get(:@grant_type) == "refresh_token"
          assert oauth_session.instance_variable_get(:@scope) == %w[foo bar]

          # from oauth server metadata url
          session = HTTPX.plugin(:oauth).with_oauth_options(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET",
          )
          oauth_session = session.send(:oauth_session)
          oauth_session.send(:load, session)

          assert oauth_session.token_endpoint.to_s == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[openid profile email address phone offline_access]

          # from hash
          HTTPX.plugin(:oauth).with_oauth_options(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET",
            scope: "all"
          ).send(:oauth_session)
          assert oauth_session.token_endpoint.to_s == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[openid profile email address phone offline_access]

          assert_raises(HTTPX::Error) do
            HTTPX.plugin(:oauth).with_oauth_options(
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
              token_endpoint_auth_method: "unsupported"
            )
          end

          assert_raises(HTTPX::Error) do
            HTTPX.plugin(:oauth).with_oauth_options(
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
              grant_type: "implicit_grant" # not supported
            )
          end

          assert_raises(ArgumentError) do
            HTTPX.plugin(:oauth).with_oauth_options("wrong")
          end
        end
      end

      def test_plugin_oauth_access_token_audience
        with_oauth_metadata do |server|
          http = HTTPX.plugin(
            :oauth,
            oauth_options: {
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
              scope: "all"
            }
          )
          http_aud = http.with_oauth_options(
            issuer: server.origin,
            client_id: "CLIENT_ID", client_secret: "SECRET",
            scope: "all", audience: "audience"
          )

          access_token = http.send(:oauth_session).fetch_access_token(http)
          aud_access_token = http_aud.send(:oauth_session).fetch_access_token(http_aud)

          assert access_token == "CLIENT-CREDS-AUTH"
          assert aud_access_token == "CLIENT-CREDS-AUTH-audience"
        end
      end

      def test_plugin_oauth_client_credentials
        with_oauth_metadata do |server|
          session = HTTPX.plugin(
            :oauth, oauth_options: {
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET", scope: "all"
            }
          )

          client_creds_uri = build_uri("/client-credentials-authed", server.origin)

          response = HTTPX.get(client_creds_uri)
          verify_status(response, 401)

          response = session.get(client_creds_uri)
          verify_status(response, 200)
        end
      end

      def test_plugin_oauth_refresh_oauth_tokens
        with_oauth_metadata do |server|
          session = HTTPX.plugin(
            :oauth, oauth_options: {
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET", scope: "all"
            }
          )
          oauth_session = session.send(:oauth_session)
          assert oauth_session.access_token.nil?
          session.refresh_oauth_tokens!
          assert !oauth_session.access_token.nil?
        end
      end

      def test_plugin_oauth_retries_refresh_token_on_retry
        with_oauth_metadata do |server|
          session = HTTPX.plugin(:retries).plugin(
            :oauth,
            oauth_options: {
              issuer: server.origin,
              token_endpoint_auth_method: "client_secret_post",
              client_id: "CLIENT_ID", client_secret: "SECRET",
              refresh_token: "REFRESH_TOKEN", access_token: "TOKEN", scope: %w[foo bar]
            }
          )

          refresh_token_uri = build_uri("/refresh-token-authed", server.origin)

          response = HTTPX.get(refresh_token_uri)
          verify_status(response, 401)

          response = session.get(refresh_token_uri)
          verify_status(response, 200)
        end
      end

      def test_plugin_oauth_deprecated_oauth_session_option
        with_oauth_metadata do |server|
          oauth_session = nil
          assert_output(nil, /DEPRECATION WARNING: option `:oauth_session` is deprecated/) do
            # from options
            oauth_session = HTTPX.plugin(:oauth).with_oauth_session(
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
              scope: "all"
            ).send(:oauth_session)
          end

          assert oauth_session.token_endpoint == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[all]
          assert oauth_session.instance_variable_get(:@audience).nil?
        end
      end

      def test_plugin_oauth_deprecated_oauth_auth
        with_oauth_metadata do |server|
          oauth_session = nil
          assert_output(nil, /DEPRECATION WARNING: `oauth_auth` is deprecated/) do
            # from options
            oauth_session = HTTPX.plugin(:oauth).oauth_auth(
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
              scope: "all"
            ).send(:oauth_session)
          end

          assert oauth_session.token_endpoint == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[all]
          assert oauth_session.instance_variable_get(:@audience).nil?
        end
      end

      def test_plugin_oauth_deprecated_with_access_token
        with_oauth_metadata do |server|
          oauth_session = nil
          assert_output(nil, /DEPRECATION WARNING: `with_access_token` is deprecated/) do
            # from oauth server metadata url
            session = HTTPX.plugin(:oauth).with_oauth_options(
              issuer: server.origin,
              client_id: "CLIENT_ID", client_secret: "SECRET",
            )
            oauth_session = session.with_access_token.send(:oauth_session)
          end

          assert oauth_session.token_endpoint == "#{server.origin}/token"
          assert oauth_session.token_endpoint_auth_method == "client_secret_basic"
          assert oauth_session.instance_variable_get(:@grant_type) == "client_credentials"
          assert oauth_session.instance_variable_get(:@scope) == %w[openid profile email address phone offline_access]
          assert oauth_session.access_token == "CLIENT-CREDS-AUTH"
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
