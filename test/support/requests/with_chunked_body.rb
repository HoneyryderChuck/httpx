# frozen_string_literal: true

module Requests
  module WithChunkedBody
    %w[post put patch delete].each do |meth|
      define_method :"test_#{meth}_chunked_body_params" do
        uri = build_uri("/#{meth}")
        response = HTTPX.with_headers("transfer-encoding" => "chunked")
                        .send(meth, uri, body: %w[this is a chunked response])
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Transfer-Encoding", "chunked")
        assert body.key?("data")
        # assert body["data"] == "thisisachunkedresponse",
        #   "unexpected body (#{body["data"]})"
      end

      define_method :"test_#{meth}_chunked_body_trailer" do
        uri = build_uri("/#{meth}")

        http = HTTPX.with_headers("transfer-encoding" => "chunked")

        total_time = start_time = nil
        trailered = false
        request = http.build_request(meth, uri, headers: { "trailer" => "X-Time-Spent" }, body: %w[this is a chunked response])
        request.on(:headers) do |_written_request|
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
        request.on(:trailers) do |written_request|
          total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          written_request.trailers["x-time-spent"] = total_time
          trailered = true
        end
        response = http.request(request)
        verify_status(response, 200)
        body = json_body(response)
        verify_header(body["headers"], "Transfer-Encoding", "chunked")
        # httpbin sadly doesn't receive trailers...
        # verify_header(body["headers"], "X-Time-Spent", total_time.to_s)
        assert body.key?("data")
        assert trailered, "trailer callback wasn't called"
        # assert body["data"] == "thisisachunkedresponse",
        #   "unexpected body (#{body["data"]})"
      end
    end
  end
end
