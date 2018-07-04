# frozen_string_literal: true

module Requests
  module Head
    def test_http_head
      uri = build_uri("/get")
      response = HTTPX.head(uri)
      verify_status(response, 200)
      verify_body_length(response, 0)
    end
  end
end
