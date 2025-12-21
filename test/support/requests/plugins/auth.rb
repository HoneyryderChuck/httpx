# frozen_string_literal: true

module Requests
  module Plugins
    module Authentication
      def test_plugin_auth
        get_uri = build_uri("/get")
        session = HTTPX.plugin(:auth)

        response = session.authorization("TOKEN").get(get_uri)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Authorization", "TOKEN")
      end

      def test_plugin_auth_with_block
        get_uri = build_uri("/get")
        session = HTTPX.plugin(:auth)

        i = 0
        response = session.authorization { "TOKEN#{i += 1}" }.get(get_uri)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Authorization", "TOKEN1")
        response = session.authorization { "TOKEN#{i += 1}" }.get(get_uri)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Authorization", "TOKEN2")
      end

      def test_plugin_auth_regenerate_on_retry
        uri = build_uri("/status/401")
        i = 0
        session = HTTPX.plugin(RequestInspector)
                       .plugin(:retries, max_retries: 1, retry_on: ->(res) { res.status == 401 })
                       .plugin(:auth, generate_token_on_retry: ->(res) { res.status == 401 })
                       .authorization { "TOKEN#{i += 1}" }
        response = session.get(uri)
        verify_status(response, 401)
        assert session.calls == 1, "expected two errors to have been sent"
        req1, req2 = session.total_requests
        assert req1.headers["authorization"] == "TOKEN1"
        assert req2.headers["authorization"] == "TOKEN2"
      end

      # Bearer Auth

      def test_plugin_bearer_auth
        get_uri = build_uri("/get")
        session = HTTPX.plugin(:auth)
        response = session.bearer_auth("TOKEN").get(get_uri)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Authorization", "Bearer TOKEN")
      end

      # Basic Auth

      def test_plugin_basic_auth
        no_auth_response = HTTPX.get(basic_auth_uri)
        verify_status(no_auth_response, 401)
        verify_header(no_auth_response.headers, "www-authenticate", "Basic realm=\"Fake Realm\"")
        no_auth_response.close

        session = HTTPX.plugin(:basic_auth)
        response = session.basic_auth(user, pass).get(basic_auth_uri)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body, "authenticated", true)
        verify_header(body, "user", user)

        invalid_response = session.basic_auth(user, "fake").get(basic_auth_uri)
        verify_status(invalid_response, 401)
      end

      # Digest

      def test_plugin_digest_auth
        session = HTTPX.plugin(:digest_auth).with_headers("cookie" => "fake=fake_value")
        response = session.digest_auth(user, pass).get(digest_auth_uri)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body, "authenticated", true)
        verify_header(body, "user", user)
      end

      %w[SHA1 SHA2 SHA256 SHA384 SHA512 RMD160].each do |alg|
        define_method :"test_plugin_digest_auth_#{alg}" do
          session = HTTPX.plugin(:digest_auth).with_headers("cookie" => "fake=fake_value")
          response = session.digest_auth(user, pass).get("#{digest_auth_uri}/#{alg}")
          verify_status(response, 200)
          body = json_body(response)
          verify_header(body, "authenticated", true)
          verify_header(body, "user", user)
        end
      end

      %w[MD5 SHA1].each do |alg|
        define_method :"test_plugin_digest_auth_#{alg}_sess" do
          start_test_servlet(DigestServer, algorithm: "#{alg}-sess") do |server|
            uri = "#{server.origin}/"
            session = HTTPX.plugin(:digest_auth).with_headers("cookie" => "fake=fake_value")
            response = session.digest_auth(user, server.get_passwd(user), hashed: true).get(uri)
            verify_status(response, 200)
            assert response.read == "yay"
          end
        end
      end

      def test_plugin_digest_auth_bypass
        session = HTTPX.plugin(:digest_auth).with_headers("cookie" => "fake=fake_value")
        response = session.get(digest_auth_uri)
        verify_status(response, 401)
        response = session.get(build_uri("/get"))
        verify_status(response, 200)
        response = session.digest_auth(user, pass).get(build_uri("/get"))
        verify_status(response, 200)
      end

      # NTLM

      if RUBY_VERSION < "3.1.0"
        # TODO: enable again once ruby-openssl 3 supports legacy ciphers
        def test_plugin_ntlm_auth
          return if origin.start_with?("https")

          start_test_servlet(NTLMServer) do |server|
            uri = "#{server.origin}/"
            HTTPX.plugin(SessionWithPool).plugin(:ntlm_auth).wrap do |http|
              # skip unless NTLM
              no_auth_response = http.get(uri)
              verify_status(no_auth_response, 401)
              no_auth_response.close

              response = http.ntlm_auth("user", "password").get(uri)
              verify_status(response, 200)

              # bypass
              response = http.get(build_uri("/get"))
              verify_status(response, 200)
              response = http.ntlm_auth("user", "password").get(build_uri("/get"))
              verify_status(response, 200)
              # invalid_response = http.ntlm_auth("user", "fake").get(uri)
              # verify_status(invalid_response, 401)
            end
          end
        end
      end

      private

      def basic_auth_uri
        build_uri("/basic-auth/#{user}/#{pass}")
      end

      def digest_auth_uri(qop = "auth")
        build_uri("/digest-auth/#{qop}/#{user}/#{pass}")
      end

      def user
        "user"
      end

      def pass
        "pass"
      end
    end
  end
end
