# frozen_string_literal: true

require "base64"

module Requests
  module Plugins
    module Authentication
    
      def test_plugin_authentication_no_auth
    
      end
    
      def test_plugin_authentication_auth
    
      end
    
      def test_plugin_authentication_no_basic_auth
        response = HTTPX.get(basic_auth_uri)
        verify_status(response.status, 401)
        verify_header(response.headers, "www-authenticate", "Basic realm=\"Fake Realm\"") 
      end

      def test_plugin_authentication_basic_auth
        client = HTTPX.plugin(:authentication)
        response = client.basic_authentication(user, pass).get(basic_auth_uri)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body, "authenticated", true)
        verify_header(body, "user", user)

        invalid_response = client.basic_authentication(user, "fake").get(basic_auth_uri)
        verify_status(invalid_response.status, 401)
      end

      def test_plugin_authentication_digest_auth
        client = HTTPX.plugin(:authentication)
        response = client.digest_authentication(user, pass).get(digest_auth_uri)
        verify_status(response.status, 200)
        body = json_body(response)
        verify_header(body, "authenticated", true)
        verify_header(body, "user", user)
      end

      private

      def basic_auth_uri
        build_uri("/basic-auth/#{user}/#{pass}")
      end

      def digest_auth_uri(qop="auth")
        build_uri("/digest-auth/#{qop}/#{user}/#{pass}")
      end

      def user
        "user"
      end

      def pass
        "pass"
      end

      def basic_auth_token
        Base64.strict_encode64("#{user}:#{pass}")
      end

    end
  end
end
