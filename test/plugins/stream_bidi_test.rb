# frozen_string_literal: true

require_relative "../test_helper"

class StreamBidiTest < Minitest::Test
  include HTTPX

  # https://github.com/HoneyryderChuck/httpx/issues/124
  # Tests that @headers_sent is reset when request transitions to :idle (retry scenario).
  # Without this fix, retried streaming requests crash with HTTP2::Error::InternalError.
  def test_headers_sent_reset_on_idle_transition
    session = HTTPX.plugin(:stream_bidi)
    request = session.build_request(
      "POST",
      "http://example.com/test",
      headers: { "content-type" => "application/json" },
      body: ["test"],
      stream: true
    )

    # Simulate first attempt: transition through states until @headers_sent = true
    request.transition(:headers)
    assert request.state == :headers, "should be in :headers state"

    request.transition(:body)
    assert request.state == :body, "should be in :body state"
    assert request.headers_sent == true, "@headers_sent should be true after transition to :body"

    # Simulate retry: transition back to :idle
    request.transition(:idle)
    assert request.state == :idle, "should be back in :idle state"

    # This is the bug fix - @headers_sent should be reset to false
    assert request.headers_sent == false, "@headers_sent should be reset to false on :idle transition"
  end

  # Verify that @closed is NOT reset on :idle transition
  # (resetting @closed would break end_stream logic)
  def test_closed_preserved_on_idle_transition
    session = HTTPX.plugin(:stream_bidi)
    request = session.build_request(
      "POST",
      "http://example.com/test",
      headers: { "content-type" => "application/json" },
      body: ["test"],
      stream: true
    )

    # Simulate: headers sent, body in progress
    request.transition(:headers)
    request.transition(:body)

    # User closes the request (signals end of data)
    request.close
    assert request.closed? == true, "request should be closed"

    # Simulate retry: transition back to :idle
    request.transition(:idle)

    # @closed should still be true (preserves user intent)
    assert request.closed? == true, "@closed should be preserved on :idle transition"
  end
end
