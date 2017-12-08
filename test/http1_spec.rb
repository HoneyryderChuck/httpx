# frozen_string_literal: true

require_relative "test_helper"

class HTTP1Test < Minitest::Spec

  def test_http_head
    uri = build_uri("/")
    response = HTTPX.head(uri)
    assert response.status == 200, "status is unexpected"
    assert response.body.to_s.bytesize == 0, "there should be no body"
  end

  def test_http_get
    uri = build_uri("/")
    response = HTTPX.get(uri)
    assert response.status == 200, "status is unexpected"
    assert response.body.to_s.bytesize == response.headers["content-length"].to_i, "didn't load the whole body"
  end

  private

  def build_uri(suffix="/")
    "#{origin}#{suffix || "/"}"
  end

  def origin
    "http://nghttp2.org/httpbin"
  end
end
