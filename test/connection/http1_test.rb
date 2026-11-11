# frozen_string_literal: true

require_relative "../test_helper"

class HTTP1ConnectionTest < Minitest::Test
  include HTTPX

  def test_reset_requests_drops_request_with_partial_response
    a = sent_request("/a", response: true)

    pending = reset_requests(a)

    assert pending.empty?, "request with a response should not be resent (pending: #{paths(pending)})"
  end

  def test_reset_requests_keeps_inflight_requests_without_response
    a = sent_request("/a")
    b = request("/b")

    pending = reset_requests(a, b)

    assert paths(pending) == %w[/a /b], "expected /a and /b to be resent (pending: #{paths(pending)})"
    assert a.state == :idle
  end

  def test_reset_requests_drops_only_requests_with_response
    a = sent_request("/a", response: true)
    b = sent_request("/b")
    c = request("/c")

    pending = reset_requests(a, b, c)

    assert paths(pending) == %w[/b /c], "expected /b and /c to be resent (pending: #{paths(pending)})"
    assert b.state == :idle
  end

  def test_reset_requests_puts_requests_ahead_of_pending_queue
    a = sent_request("/a")
    queued = request("/queued")

    pending = reset_requests(a, pending: [queued])

    assert paths(pending) == %w[/a /queued], "expected /a ahead of /queued (pending: #{paths(pending)})"
  end

  private

  def reset_requests(*requests, pending: [])
    parser = Connection::HTTP1.new(Buffer.new(16_384), pending, options)
    requests.each { |req| assert parser.send(req) }
    parser.reset_requests
    assert parser.requests.empty?
    pending
  end

  def request(path)
    Request.new("GET", "http://example.com#{path}", options)
  end

  def sent_request(path, response: false)
    req = request(path)
    req.transition(:headers)
    req.transition(:body)
    req.transition(:done)
    req.response = Response.new(req, 200, "1.1", {}) if response
    req
  end

  def paths(requests)
    requests.map(&:path)
  end

  def options
    @options ||= Options.new
  end
end
