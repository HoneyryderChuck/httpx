# frozen_string_literal: true

begin
  # upcoming 2.0
  require "datadog"
rescue LoadError
  require "ddtrace"
end

require "test_helper"
require "support/http_helpers"
require "httpx/adapters/faraday"
require_relative "datadog_helpers"

DATADOG_VERSION = defined?(DDTrace) ? DDTrace::VERSION : Datadog::VERSION

class FaradayDatadogTest < Minitest::Test
  include HTTPHelpers
  include DatadogHelpers
  include FaradayHelpers

  def test_faraday_datadog_successful_get_request
    set_datadog
    uri = URI(build_uri("/status/200"))

    response = faraday_connection.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_faraday_datadog_successful_post_request
    set_datadog
    uri = URI(build_uri("/status/200"))

    response = faraday_connection.post(uri, "bla")
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, verb: "POST", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_faraday_datadog_server_error_request
    set_datadog
    uri = URI(build_uri("/status/500"))

    ex = assert_raises(Faraday::ServerError) { faraday_connection.get(uri) }

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(ex.response[:status], verb: "GET", uri: uri, error: "Error 500")

    verify_distributed_headers(request_headers(ex.response))
  end

  def test_faraday_datadog_client_error_request
    set_datadog
    uri = URI(build_uri("/status/404"))

    ex = assert_raises(Faraday::ResourceNotFound) { faraday_connection.get(uri) }

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(ex.response[:status], verb: "GET", uri: uri, error: "Error 404")
    verify_distributed_headers(request_headers(ex.response))
  end

  def test_faraday_datadog_some_other_error
    set_datadog
    uri = URI("http://unexisting/")

    assert_raises(HTTPX::NativeResolveError) { faraday_connection.get(uri) }

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(nil, verb: "GET", uri: uri, error: "HTTPX::NativeResolveError")
  end

  def test_faraday_datadog_host_config
    uri = URI(build_uri("/status/200"))
    set_datadog(describe: /#{uri.host}/) do |http|
      http.service_name = "httpbin"
      http.split_by_domain = false
    end

    response = faraday_connection.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, service: "httpbin", verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_faraday_datadog_split_by_domain
    uri = URI(build_uri("/status/200"))
    set_datadog do |http|
      http.split_by_domain = true
    end

    response = faraday_connection.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, service: uri.host, verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_faraday_datadog_distributed_headers_disabled
    set_datadog(distributed_tracing: false)
    uri = URI(build_uri("/status/200"))

    sampling_priority = 10
    response = trace_with_sampling_priority(sampling_priority) do
      faraday_connection.get(uri)
    end
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_no_distributed_headers(request_headers(response))
    verify_analytics_headers(span)
  end unless ENV.key?("CI") # TODO: https://github.com/DataDog/dd-trace-rb/issues/4308

  def test_faraday_datadog_distributed_headers_sampling_priority
    set_datadog
    uri = URI(build_uri("/status/200"))

    sampling_priority = 10
    response = trace_with_sampling_priority(sampling_priority) do
      faraday_connection.get(uri)
    end

    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response), span: span, sampling_priority: sampling_priority)
    verify_analytics_headers(span)
  end unless ENV.key?("CI") # TODO: https://github.com/DataDog/dd-trace-rb/issues/4308

  def test_faraday_datadog_analytics_enabled
    set_datadog(analytics_enabled: true)
    uri = URI(build_uri("/status/200"))

    response = faraday_connection.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_analytics_headers(span, sample_rate: 1.0)
  end

  def test_faraday_datadog_analytics_sample_rate
    set_datadog(analytics_enabled: true, analytics_sample_rate: 0.5)
    uri = URI(build_uri("/status/200"))

    response = faraday_connection.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_analytics_headers(span, sample_rate: 0.5)
  end

  private

  def setup
    super
    Datadog.registry[:faraday].reset_configuration!
  end

  def teardown
    super
    Datadog.registry[:faraday].reset_configuration!
  end

  def datadog_service_name
    :faraday
  end

  def origin(orig = httpbin)
    "http://#{orig}"
  end
end
