# frozen_string_literal: true

require_relative "test_helper"

class HeadersTest < Minitest::Test
  include HTTPX

  def test_headers_set
    h1 = Headers.new
    assert h1["accept"].nil?, "unexpected header value"
    assert h1["accept"] = "text/html"
    assert h1["accept"] == "text/html", "unexpected header value"
    h1["Accept-Encoding"] = "gzip"
    assert h1["accept-encoding"] == "gzip", "unexpected header value"
    assert h1["Accept-Encoding"] == "gzip", "unexpected header value"
  end

  def test_headers_delete
    h1 = Headers.new("accept" => "text/html")
    assert h1["accept"] == "text/html", "unexpected header value"
    h1.delete("accept")
    assert h1["accept"].nil?, "unexpected header value"
  end

  def test_headers_add
    h1 = Headers.new("accept" => "text/html")
    h1.add("accept", "application/xhtml+xml")
    assert h1["accept"] == "text/html, application/xhtml+xml", "unexpected header value"
    assert h1.get("accept") == %w[text/html application/xhtml+xml], "unexpected header value"
  end

  def test_header_key?
    h1 = Headers.new("accept" => "text/html")
    assert h1.key?("accept"), "header field should exist"
    assert !h1.key?("content-encoding"), "header field should no exist"
  end

  def test_header_each
    h1 = Headers.new("accept" => "text/html")
    enum = h1.each
    ha = enum.to_a
    assert ha == [%w[accept text/html]], "unexpected array representation"
  end

  private

  def resource
    @resource ||= Headers.new({})
  end
end
