# frozen_string_literal: true

require_relative "test_helper"

class AltSvcTest < Minitest::Test
  include HTTPX

  def test_altsvc_cache
    assert AltSvc.cached_altsvc("http://www.example-altsvc-cache.com").empty?
    AltSvc.cached_altsvc_set("http://www.example-altsvc-cache.com", { "origin" => "http://alt.example-altsvc-cache.com", "ma" => 2 })
    entries = AltSvc.cached_altsvc("http://www.example-altsvc-cache.com")
    assert !entries.empty?
    entry = entries.first
    assert entry["origin"] == "http://alt.example-altsvc-cache.com"
    sleep 3
    assert AltSvc.cached_altsvc("http://www.example-altsvc-cache.com").empty?
  end

  def test_altsvc_scheme
    assert_equal "https", AltSvc.parse_altsvc_scheme("h2")
    assert_equal "http", AltSvc.parse_altsvc_scheme("h2c")
    assert AltSvc.parse_altsvc_scheme("wat").nil?
  end

  def test_altsvc_parse_svc
    assert_equal [[URI("https://alt.example.com"), { "proto" => "h2" }]], AltSvc.parse("h2=\"alt.example.com\"").to_a
  end

  def test_altsvc_parse_multiple_svc
    assert_equal [[URI("https://alt.example.com"), { "proto" => "h2" }], [URI("https://alt2.example.com"), { "proto" => "h2" }]],
                 AltSvc.parse("h2=\"alt.example.com\", h2=\"alt2.example.com\"").to_a
  end

  def test_altsvc_parse_svc_with_port
    assert_equal [[URI("https://alt.example.com:8000"), { "proto" => "h2" }]], AltSvc.parse("h2=\"alt.example.com:8000\"").to_a
  end

  def test_altsvc_parse_multiple_svc_with_port
    assert_equal [[URI("https://alt.example.com:8000"), { "proto" => "h2" }], [URI("https://alt2.example.com:8000"), { "proto" => "h2" }]],
                 AltSvc.parse("h2=\"alt.example.com:8000\", h2=\"alt2.example.com:8000\"").to_a
  end

  def test_altsvc_parse_svcs
    assert_equal [[URI("https://alt.example.com:8000"), { "proto" => "h2" }], [URI("https://alt3.example.com"), { "proto" => "h2" }]],
                 AltSvc.parse("h2=\"alt.example.com:8000\", h2=\":443\"", host: "alt3.example.com").to_a
  end

  def test_altsvc_parse_svc_prop
    assert_equal [[URI("https://alt.example.com:8000"), { "ma" => "60", "proto" => "h2" }]],
                 AltSvc.parse("h2=\"alt.example.com:8000\"; ma=60").to_a
  end

  def test_altsvc_parse_multiple_svc_prop
    assert_equal [[URI("https://alt.example.com"), { "ma" => "60", "proto" => "h2" }],
                  [URI("https://alt2.example.com"), { "proto" => "h2", "ma" => "60" }]],
                 AltSvc.parse("h2=\"alt.example.com\", h2=\"alt2.example.com\"; ma=60").to_a
  end

  def test_altsvc_parse_svc_props
    assert_equal [[URI("https://alt.example.com:8000"), { "ma" => "60", "persist" => "1", "proto" => "h2" }]],
                 AltSvc.parse("h2=\"alt.example.com:8000\"; ma=60; persist=1").to_a
  end

  def test_altsvc_parse_svc_with_versions
    assert_equal [[URI("https://alt3.example.com"), { "ma" => "2592000", "v" => "\"46,43,39\"", "proto" => "quic" }]],
                 AltSvc.parse("quic=\":443\"; ma=2592000; v=\"46,43,39\"", host: "alt3.example.com").to_a
  end

  def test_altsvc_parse_svcs_with_props
    assert_equal [[URI("https://alt3.example.com"), { "ma" => "2592000", "v" => "\"46,43\"", "proto" => "quic" }],
                  [URI("https://alt3.example.com"), { "ma" => "2592000", "proto" => "h3-Q046" }],
                  [URI("https://alt3.example.com"), { "ma" => "2592000", "proto" => "h3-Q043" }]],
                 AltSvc.parse("quic=\":443\"; ma=2592000; v=\"46,43\",h3-Q046=\":443\"; ma=2592000,h3-Q043=\":443\"; ma=2592000",
                              host: "alt3.example.com").to_a
  end

  def test_altsvc_clear_cache
    AltSvc.cached_altsvc_set("http://www.example-clear-cache.com", { "origin" => "http://alt.example-clear-cache.com", "ma" => 2 })
    entries = AltSvc.cached_altsvc("http://www.example-clear-cache.com")
    assert !entries.empty?

    req = Request.new("GET", "http://www.example-clear-cache.com/", Options.new)
    res = Response.new(req, 200, "2.0", { "alt-svc" => "clear" })

    AltSvc.emit(req, res) {}

    entries = AltSvc.cached_altsvc("http://www.example-clear-cache.com")
    assert entries.empty?
  end
end
