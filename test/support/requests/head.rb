# frozen_string_literal: true

module Requests
  module Head 
    def test_http_head
      uri = build_uri("/")
      response = HTTPX.head(uri)
      assert response.status == 200, "status is unexpected"
      assert response.body.to_s.bytesize == 0, "there should be no body"
    end
  end
end

