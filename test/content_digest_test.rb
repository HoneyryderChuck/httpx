# frozen_string_literal: true

require_relative "support/http_helpers"

class HTTPXContentDigestTest < Minitest::Test
  def test_plugin_content_digest_default_request
    request = HTTPX.plugin(:content_digest)
                   .build_request(
                     "POST",
                     "http://domain.com",
                     body: StringIO.new("{\"hello\": \"world\"}\n")
                   )

    expected_digest = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"

    assert request.headers["content-digest"] == expected_digest,
           "expected: \"#{expected_digest}\", got \"#{request.headers["content-digest"]}\" inspected"
  end

  def test_plugin_content_digest_request_sha512
    request = HTTPX.plugin(:content_digest, content_digest_algorithm: "sha-512")
                   .build_request(
                     "POST",
                     "http://domain.com",
                     body: StringIO.new("{\"hello\": \"world\"}\n")
                   )

    expected_digest = "sha-512=:YMAam51Jz/jOATT6/zvHrLVgOYTGFy1d6GJiOHTohq4yP+pgk4vf2aCsyRZOtw8MjkM7iw7yZ/WkppmM44T3qg==:"
    assert request.headers["content-digest"] == expected_digest,
           "expected: \"#{expected_digest}\", got \"#{request.headers["content-digest"]}\" inspected"
  end

  def test_plugin_content_digest_from_json
    request = HTTPX.plugin(:content_digest)
                   .build_request(
                     "POST",
                     "http://domain.com",
                     json: { hello: "world" }
                   )

    # json is encoded without whitespace / newline, so digest differs from RFC
    expected_digest = "sha-256=:k6I5cakU5erL8KjSUVTNownDwccvu5kU1Hxg88toFYg=:"

    assert request.headers["content-digest"] == expected_digest,
           "expected: \"#{expected_digest}\", got \"#{request.headers["content-digest"]}\" inspected"
  end

  def test_plugin_content_digest_from_file
    json_file = File.open(File.expand_path("support/fixtures/hello_world.json", __dir__))
    request = HTTPX.plugin(:content_digest)
                   .build_request(
                     "POST",
                     "http://domain.com",
                     body: json_file
                   )
    json_file.close

    expected_digest = "sha-256=:RK/0qy18MlBSVnWgjwz6lZEWjP/lF5HF9bvEF8FabDg=:"

    assert request.headers["content-digest"] == expected_digest,
           "expected: \"#{expected_digest}\", got \"#{request.headers["content-digest"]}\" inspected"
  end

  def test_plugin_content_digest_deflate
    request = HTTPX.plugin(:content_digest)
                   .build_request(
                     "POST",
                     "http://domain.com",
                     headers: {
                       "content-encoding" => "deflate",
                     },
                     body: "{\"hello\": \"world\"}\n"
                   )

    expected_digest = "sha-256=:2BPbFIfCAhjEJQF/2ifXfGqoq39DbqbVbk6H3Ann5sE=:"

    assert request.headers["content-digest"] == expected_digest,
           "expected: \"#{expected_digest}\", got \"#{request.headers["content-digest"]}\" inspected"
  end

  def test_plugin_content_digest_skip_digest
    request = HTTPX.plugin(:content_digest, encode_content_digest: false)
                   .build_request(
                     "POST",
                     "http://domain.com",
                     body: "{\"hello\": \"world\"}\n"
                   )

    assert request.headers["content-digest"].nil?
  end
end
