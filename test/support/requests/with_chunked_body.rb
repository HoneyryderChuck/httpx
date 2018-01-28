# frozen_string_literal: true

module Requests
  module WithChunkedBody
    %w[post put patch delete].each do |meth|
      # define_method :"test_#{meth}_chunked_body_params" do
      #   uri = build_uri("/#{meth}")
      #   response = HTTPX.headers("transfer-encoding" => "chunked")
      #                   .send(meth, uri, body: %w[this is a chunked response])
      #   verify_status(response.status, 200)
      #   body = json_body(response)
      #   verify_header(body["headers"], "Transfer-Encoding", "chunked")
      #   assert body.key?("data")
      #   assert body["data"] == "thisisachunkedresponse"
      # end
    end
  end
end
