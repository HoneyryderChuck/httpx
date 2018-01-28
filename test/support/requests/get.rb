# frozen_string_literal: true

module Requests
  module Get
    def test_http_get
      uri = build_uri("/")
      response = HTTPX.get(uri)
      verify_status(response.status, 200)
      verify_body_length(response)
    end
  end
end
