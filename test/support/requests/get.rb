# frozen_string_literal: true

module Requests
  module Get
    def test_http_get
      uri = build_uri("/")
      response = HTTPX.get(uri)
      assert response.status == 200, "status is unexpected"
      assert response.body.to_s.bytesize == response.headers["content-length"].to_i, "didn't load the whole body"
    end
  end
end 
