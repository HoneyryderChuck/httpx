# frozen_string_literal: true

require "logger"
require "stringio"
require "sentry-ruby"
require "test_helper"
require "support/http_helpers"
require "httpx/adapters/sentry"

class SentryTest < Minitest::Test
  include HTTPHelpers

  DUMMY_DSN = "http://12345:67890@sentry.localdomain/sentry/42"

  def test_sentry_send_yes_pii
    before_pii = Sentry.configuration.send_default_pii
    begin
      Sentry.configuration.send_default_pii = true

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      uri = build_uri("/get")

      response = HTTPX.get(uri, params: { "foo" => "bar" })

      verify_status(response, 200)
      verify_spans(transaction, response, description: "GET #{uri}?foo=bar")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      assert crumb.category == "httpx"
      assert crumb.data ==  { status: 200, method: "GET", url: "#{uri}?foo=bar" }
    ensure
      Sentry.configuration.send_default_pii = before_pii
    end
  end

  def test_sentry_send_no_pii
    before_pii = Sentry.configuration.send_default_pii
    begin
      Sentry.configuration.send_default_pii = false

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      uri = build_uri("/get")

      response = HTTPX.get(uri, params: { "foo" => "bar" })

      verify_status(response, 200)
      verify_spans(transaction, response, description: "GET #{uri}")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      assert crumb.category == "httpx"
      assert crumb.data ==  { status: 200, method: "GET", url: uri }
    ensure
      Sentry.configuration.send_default_pii = before_pii
    end
  end

  def test_sentry_post_request
    before_pii = Sentry.configuration.send_default_pii
    begin
      Sentry.configuration.send_default_pii = true
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      uri = build_uri("/post")
      response = HTTPX.post(uri, form: { foo: "bar" })
      verify_status(response, 200)
      verify_spans(transaction, response, verb: "POST")

      crumb = Sentry.get_current_scope.breadcrumbs.peek
      assert crumb.category == "httpx"
      assert crumb.data == { status: 200, method: "POST", url: uri, body: "foo=bar" }
    ensure
      Sentry.configuration.send_default_pii = before_pii
    end
  end

  def test_sentry_multiple_requests
    transaction = Sentry.start_transaction
    Sentry.get_current_scope.set_span(transaction)

    responses = HTTPX.get(build_uri("/status/200"), build_uri("/status/404"))
    verify_status(responses[0], 200)
    verify_status(responses[1], 404)
    verify_spans(transaction, *responses)
  end

  def test_sentry_server_error_request
    transaction = Sentry.start_transaction
    Sentry.get_current_scope.set_span(transaction)

    uri = URI("http://unexisting/")

    response = HTTPX.get(uri)

    verify_error_response(response, /name or service not known/)
    assert response.is_a?(HTTPX::ErrorResponse), "response should contain errors"
    verify_spans(transaction, response, verb: "GET")
    crumb = Sentry.get_current_scope.breadcrumbs.peek
    assert crumb.category == "httpx"
    assert crumb.data == { error: "name or service not known", method: "GET", url: uri.to_s }
  end

  private

  def verify_spans(transaction, *responses, verb: nil, description: nil)
    assert transaction.span_recorder.spans.count == responses.size + 1
    assert transaction.span_recorder.spans[0] == transaction

    response_spans = transaction.span_recorder.spans[1..-1]

    responses.each_with_index do |response, idx|
      request_span = response_spans[idx]
      assert request_span.op == "httpx.client"
      assert !request_span.start_timestamp.nil?
      assert !request_span.timestamp.nil?
      assert request_span.start_timestamp != request_span.timestamp
      assert request_span.description == (description || "#{verb || "GET"} #{response.uri}")
      if response.is_a?(HTTPX::ErrorResponse)
        assert request_span.data == { error: response.error.message }
      else
        assert request_span.data == { status: response.status }
      end
    end
  end

  def setup
    super

    mock_io = StringIO.new
    mock_logger = Logger.new(mock_io)

    Sentry.init do |config|
      config.traces_sample_rate = 1.0
      config.logger = mock_logger
      config.dsn = DUMMY_DSN
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
      config.breadcrumbs_logger = [:http_logger]
      config.enabled_patches << :httpx
      # so the events will be sent synchronously for testing
    end
  end

  def origin
    "https://#{httpbin}"
  end
end
