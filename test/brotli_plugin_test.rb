# frozen_string_literal: true

require "minitest/autorun"
require "httpx"

class BrotliPluginTest < Minitest::Test
  def test_streaming_response_body_decodes_incremental_brotli_chunks
    response = HTTPX::Response.new(
      request,
      200,
      "2.0",
      {
        "content-encoding" => "br",
        "content-length" => compressed_payload.bytesize.to_s,
      }
    )

    compressed_payload.bytes.each_slice(7) do |chunk|
      response << chunk.pack("C*")
    end

    assert_equal payload, response.body.to_s
  ensure
    response&.close
  end

  def test_streaming_request_body_encodes_incremental_brotli_chunks
    headers = HTTPX::Headers.new("content-encoding" => "br")
    body = default_options.request_body_class.new(headers, default_options, body: streaming_body)
    compressed_chunks = body.each.to_a

    refute body.unbounded_body?
    assert_equal compressed_chunks.join.bytesize.to_s, headers["content-length"]
    assert_operator compressed_chunks.length, :>, 1
    assert_equal payload, ::Brotli.inflate(compressed_chunks.join)
  ensure
    body&.close
  end

  private

  def session
    @session ||= HTTPX.plugin(:brotli)
  end

  def request
    HTTPX::Request.new("GET", "https://example.test/brotli", default_options)
  end

  def payload
    @payload ||= (File.binread(File.join(__dir__, "support", "fixtures", "image.jpg")) * 4).b
  end

  def default_options
    session.__send__(:default_options)
  end

  def compressed_payload
    @compressed_payload ||= ::Brotli.deflate(payload)
  end

  def payload_chunks
    @payload_chunks ||= payload.bytes.each_slice(1024).map { |chunk| chunk.pack("C*") }
  end

  def streaming_body
    chunks = payload_chunks

    Object.new.tap do |stream|
      stream.define_singleton_method(:each) do |&block|
        chunks.each(&block)
      end
    end
  end
end
