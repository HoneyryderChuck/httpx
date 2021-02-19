# frozen_string_literal: true

require_relative "test_helper"

class AltSvcTest < Minitest::Test
  include HTTPX

  def test_altsvc_cache
    assert AltSvc.cached_altsvc("http://www.example.com").empty?
    AltSvc.cached_altsvc_set("http://www.example.com", { "origin" => "http://alt.example.com", "ma" => 2 })
    entries = AltSvc.cached_altsvc("http://www.example.com")
    assert !entries.empty?
    entry = entries.first
    assert entry["origin"] == "http://alt.example.com"
    sleep 3
    assert AltSvc.cached_altsvc("http://www.example.com").empty?
  end

  def test_altsvc_parse_svc
    assert [["h2=alt.example.com", {}]], AltSvc.parse("h2=alt.example.com").to_a
  end

  def test_altsvc_parse_svc_with_port
    assert [["h2=alt.example.com:8000", {}]], AltSvc.parse("h2=\"alt.example.com:8000\"").to_a
  end

  def test_altsvc_parse_svcs
    assert [["h2=alt.example.com:8000", {}], ["h2=:8000", {}]],
           AltSvc.parse("h2=\"alt.example.com:8000\", h2=\":443\"").to_a
  end

  def test_altsvc_parse_svc_prop
    assert [["h2=alt.example.com:8000'", { "ma" => "60" }]],
           AltSvc.parse("h2=\"alt.example.com:8000\"; ma=60").to_a
  end

  def test_altsvc_parse_svc_props
    assert [["h2=alt.example.com:8000", { "persist" => "1" }]],
           AltSvc.parse("h2=\"alt.example.com:8000\"; ma=60; persist=1").to_a
  end

  def test_altsvc_parse_svc_with_versions
    assert [["quic=:443", { "ma" => "2592000", "v" => "46,43,39" }]],
           AltSvc.parse("quic=\":443\"; ma=2592000; v=\"46,43,39\"").to_a
  end

  def test_altsvc_parse_svcs_with_props
    assert [["quic=:443", { "ma" => "2592000", "v" => "46,43" }],
            ["h3-Q046=:443", { "ma" => "2592000" }],
            ["h3-Q043=:443", { "ma" => "2592000" }]],
           AltSvc.parse("quic=\":443\"; ma=2592000; v=\"46,43\",h3-Q046=\":443\"; ma=2592000,h3-Q043=\":443\"; ma=2592000").to_a
  end
end
