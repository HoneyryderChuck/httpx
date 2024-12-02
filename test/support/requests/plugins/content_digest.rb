# frozen_string_literal: true

module Requests
  module Plugins
    module ContentDigest
      IGNORE_MISSING_HEADER = ->(res) { res.headers.key?("content-digest") }

      def test_content_digest_missing_no_validation
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest, validate_content_digest: false)

          %w[/no_content_digest /invalid_content_digest].each do |path|
            response = http.get(server.origin + path)

            verify_status(response, 200)
          end
        end
      end

      def test_content_digest_missing_validation_if_present
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest, validate_content_digest: IGNORE_MISSING_HEADER)

          response = http.get("#{server.origin}/no_content_digest")

          verify_status(response, 200)
        end
      end

      def test_content_digest_missing_validation_always
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest)

          response = http.get("#{server.origin}/no_content_digest")

          verify_error_response(response, HTTPX::Plugins::ContentDigest::MissingContentDigestError)
        end
      end

      def test_content_digest_present_validation_if_present
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest, validate_content_digest: IGNORE_MISSING_HEADER)

          response = http.get("#{server.origin}/valid_content_digest")

          verify_status(response, 200)
        end
      end

      def test_content_digest_present_validation_always
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest)

          response = http.get("#{server.origin}/valid_content_digest")

          verify_status(response, 200)
        end
      end

      def test_content_digest_invalid_validation_if_present
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest, validate_content_digest: IGNORE_MISSING_HEADER)

          response = http.get("#{server.origin}/invalid_content_digest")

          verify_error_response(response, HTTPX::Plugins::ContentDigest::InvalidContentDigestError)
        end
      end

      def test_content_digest_invalid_validation_always
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest)

          response = http.get("#{server.origin}/invalid_content_digest")

          verify_error_response(response, HTTPX::Plugins::ContentDigest::InvalidContentDigestError)
        end
      end

      def test_content_digest_multiple_validation_always
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest)

          response = http.get("#{server.origin}/multiple_content_digests")

          verify_status(response, 200)
        end
      end

      def test_content_digest_gzip_encoding
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest)

          response = http.get("#{server.origin}/gzip_content_digest")

          verify_status(response, 200)
        end
      end

      def test_content_digest_large_response_body
        start_test_servlet(ContentDigestServer) do |server|
          http = HTTPX.plugin(:content_digest)

          response = http.get("#{server.origin}/large_body_content_digest")

          verify_status(response, 200)
        end
      end
    end
  end
end
