# frozen_string_literal: true

require_relative "test"

class ContentDigestServer < TestServer
  class NoDigestApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "{\"hello\": \"world\"}"
      res["Content-Type"] = "application/json"
    end
  end

  class ValidDigestApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "{\"hello\": \"world\"}"
      res["Content-Type"] = "application/json"
      res["Content-Digest"] = "sha-256=:X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=:"
    end
  end

  class InvalidDigestApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "{\"hello\": \"world\"}"
      res["Content-Type"] = "application/json"
      res["Content-Digest"] = "sha-256=:Y59F0rPplrrsweut9mPKSKM4PXEVpzXyCg8lcv0ECQF=:"
    end
  end

  class MultipleDigestsApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "{\"hello\": \"world\"}"
      res["Content-Type"] = "application/json"
      digest256 = "sha-256=:X48E9qOokqqrvdts8nOJRJN3OWDUoyWxBf7kbu9DBPE=:"
      digest512 = "sha-512:WZDPaVn/7XgHaAy8pmojAkGWoRx2UFChF41A2svX+TaPm+AbwAgBWnrIiYllu7BNNyealdVLvRwEmTHWXvJwew==:"
      res["Content-Digest"] = [digest256, digest512].join(",")
    end
  end

  class GzipDigestApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "\x1F\x8B\b\x00\xBB\xD6Eg\x00\x03\xABV\xCAH\xCD\xC9\xC9W\xB2RP*\xCF/\xCAIQ\xAA\x05\x00\"\xAE\xA3\x86\x12\x00\x00\x00"
      res["Content-Type"] = "application/json"
      res["Content-Encoding"] = "gzip"
      res["Content-Digest"] = "sha-256=:oswx8nqtHLL4Gky0pTtr8lKNF/IYNtAA4OUjONh+0Ns=:"
    end
  end

  class LargeBodyApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "a#{"a" * HTTPX::Options::MAX_BODY_THRESHOLD_SIZE}"
      res["Content-Digest"] = "sha-256=:#{OpenSSL::Digest.base64digest("sha256", res.body)}:"
    end
  end

  def initialize(options = {})
    super
    mount("/no_content_digest", NoDigestApp)
    mount("/valid_content_digest", ValidDigestApp)
    mount("/invalid_content_digest", InvalidDigestApp)
    mount("/multiple_content_digests", MultipleDigestsApp)
    mount("/gzip_content_digest", GzipDigestApp)
    mount("/large_body_content_digest", LargeBodyApp)
  end
end
