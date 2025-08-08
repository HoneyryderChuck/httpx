# frozen_string_literal: true

module Requests
  module Compression
    def test_compression_accepts
      url = "https://github.com"

      response = HTTPX.get(url)
      skip if response == 429
      verify_status(response, 200)
      assert response.body.encodings == %w[gzip], "response should be sent with gzip encoding"
      response.close
    end

    def test_compression_identity_post
      uri = build_uri("/post")
      response = HTTPX.with_headers("content-encoding" => "identity")
                      .post(uri, body: "a" * 8012)
      verify_status(response, 200)
      body = json_body(response)
      verify_header(body["headers"], "Content-Type", "application/octet-stream")
      compressed_data = body["data"]
      assert compressed_data.bytesize == 8012, "body shouldn't have been compressed"
    end

    def test_compression_gzip
      uri = build_uri("/gzip")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      assert response.headers["content-length"].to_i != response.body.bytesize
      body = json_body(response)
      assert body["gzipped"], "response should be gzipped"
    end

    def test_compression_gzip_do_not_decompress
      uri = build_uri("/gzip")
      response = HTTPX.get(uri, decompress_response_body: false)
      verify_status(response, 200)
      assert response.headers["content-length"].to_i == response.body.bytesize
    end

    def test_compression_gzip_post
      uri = build_uri("/post")
      response = HTTPX.with_headers("content-encoding" => "gzip")
                      .post(uri, body: "a" * 8012)
      verify_status(response, 200)
      body = json_body(response)
      verify_header(body["headers"], "Content-Type", "application/octet-stream")
      compressed_data = body["data"]
      compressed_data = compressed_data.delete_prefix("data:application/octet-stream;base64,")
      compressed_data = Base64.decode64(compressed_data)
      assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      assert inflate_test_data(compressed_data) == "a" * 8012
    end

    def test_compression_gzip_post_already_compressed
      uri = build_uri("/post")
      gzip_body = Zlib.gzip("a" * 8012)

      response = HTTPX.with(
        compress_request_body: false,
        headers: { "content-encoding" => "gzip" }
      ).post(uri, body: gzip_body)
      verify_status(response, 200)
      body = json_body(response)
      verify_header(body["headers"], "Content-Type", "application/octet-stream")
      compressed_data = body["data"]
      compressed_data = compressed_data.delete_prefix("data:application/octet-stream;base64,")
      compressed_data = Base64.decode64(compressed_data)
      assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      assert inflate_test_data(compressed_data) == "a" * 8012
    end

    def test_compression_deflate
      uri = build_uri("/deflate")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      body = json_body(response)
      assert body["deflated"], "response should be deflated"
    end

    def test_compression_deflate_post
      uri = build_uri("/post")
      response = HTTPX.with_headers("content-encoding" => "deflate")
                      .post(uri, body: "a" * 8012)
      verify_status(response, 200)
      body = json_body(response)
      verify_header(body["headers"], "Content-Type", "application/octet-stream")
      compressed_data = body["data"]
      compressed_data = compressed_data.delete_prefix("data:application/octet-stream;base64,")
      compressed_data = Base64.decode64(compressed_data)
      assert compressed_data.bytesize < 8012, "body hasn't been compressed"
      assert inflate_test_data(compressed_data) == "a" * 8012
    end

    # regression test
    def test_compression_no_content_length
      # run this only for http/1.1 mode, as this is a local test server
      return unless origin.start_with?("http://")

      start_test_servlet(NoContentLengthServer) do |server|
        uri = build_uri("/", server.origin)
        response = HTTPX.get(uri)
        verify_status(response, 200)
        body = response.body.to_s
        assert body == "helloworld"
      end
    end

    def test_compression_ignore_encoding_on_range
      uri = build_uri("/get")
      response = HTTPX.get(uri)
      verify_status(response, 200)
      body = json_body(response)
      assert body["headers"].key?("Accept-Encoding")

      response = HTTPX.get(uri, headers: { "range" => "bytes=100-200" })
      body = json_body(response)
      assert !body["headers"].key?("Accept-Encoding")
    end

    private

    def inflate_test_data(string)
      zstream = Zlib::Inflate.new(Zlib::MAX_WBITS + 32)
      buf = zstream.inflate(string)
      zstream.finish
      zstream.close
      buf
    end
  end
end
