# frozen_string_literal: true

require_relative "test_helper"

class AltSvcTest < Minitest::Test
  include HTTPX

  def test_parse
    assert [["h2=alt.example.com", {}]], AltSvc.parse("h2=alt.example.com").to_a
    assert [["h2=alt.example.com:8000", {}]], AltSvc.parse("h2=\"alt.example.com:8000\"").to_a
    assert [["h2=alt.example.com:8000", {}], ["h2=:8000", {}]],
           AltSvc.parse("h2=\"alt.example.com:8000\", h2=\":443\"").to_a
    assert [["h2=alt.example.com:8000'", { "ma" => "60" }]],
           AltSvc.parse("h2=\"alt.example.com:8000\"; ma=60").to_a
    assert [["h2=alt.example.com:8000", { "persist" => "1" }]],
           AltSvc.parse("h2=\"alt.example.com:8000\"; ma=60; persist=1").to_a
  end
end
