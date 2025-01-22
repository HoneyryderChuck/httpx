# frozen_string_literal: true

begin
  # upcoming 2.0
  require "datadog"
rescue LoadError
  require "ddtrace"
end

require "test_helper"
require "support/http_helpers"
require "httpx/adapters/datadog"
require_relative "datadog_helpers"

class DatadogTest < Minitest::Test
  include HTTPHelpers
  include DatadogHelpers

  def test_datadog_successful_get_request
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_successful_post_request
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.post(uri, body: "bla")
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, verb: "POST", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_successful_multiple_requests
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    get_response, post_response = HTTPX.request([["GET", uri], ["POST", uri]])
    verify_status(get_response, 200)
    verify_status(post_response, 200)

    assert fetch_spans.size == 2, "expected to have 2 spans"
    get_span, post_span = fetch_spans
    verify_instrumented_request(get_response.status, span: get_span, verb: "GET", uri: uri)
    verify_instrumented_request(post_response.status, span: post_span, verb: "POST", uri: uri)
    verify_distributed_headers(request_headers(get_response), span: get_span)
    verify_distributed_headers(request_headers(post_response), span: post_span)
    verify_analytics_headers(get_span)
    verify_analytics_headers(post_span)
  end

  def test_datadog_server_error_request
    set_datadog
    uri = URI(build_uri("/status/500", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 500)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, verb: "GET", uri: uri, error: "HTTPX::HTTPError")
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_client_error_request
    set_datadog
    uri = URI(build_uri("/status/404", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 404)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, verb: "GET", uri: uri, error: "HTTPX::HTTPError")
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_some_other_error
    set_datadog
    uri = URI("http://unexisting/")

    response = HTTPX.get(uri)
    assert response.is_a?(HTTPX::ErrorResponse), "response should contain errors"

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(nil, verb: "GET", uri: uri, error: "HTTPX::NativeResolveError")
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_host_config
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))
    set_datadog(describe: /#{uri.host}/) do |http|
      http.service_name = "httpbin"
      http.split_by_domain = false
    end

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, service: "httpbin", verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_split_by_domain
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))
    set_datadog do |http|
      http.split_by_domain = true
    end

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response.status, service: uri.host, verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response))
  end

  def test_datadog_distributed_headers_disabled
    set_datadog(distributed_tracing: false)
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    sampling_priority = 10
    response = trace_with_sampling_priority(sampling_priority) do
      HTTPX.get(uri)
    end
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_no_distributed_headers(request_headers(response))
    verify_analytics_headers(span)
  end

  def test_datadog_distributed_headers_sampling_priority
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    sampling_priority = 10
    response = trace_with_sampling_priority(sampling_priority) do
      HTTPX.get(uri)
    end

    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_distributed_headers(request_headers(response), span: span, sampling_priority: sampling_priority)
    verify_analytics_headers(span)
  end

  def test_datadog_analytics_enabled
    set_datadog(analytics_enabled: true)
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_analytics_headers(span, sample_rate: 1.0)
  end

  def test_datadog_analytics_sample_rate
    set_datadog(analytics_enabled: true, analytics_sample_rate: 0.5)
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri)
    verify_analytics_headers(span, sample_rate: 0.5)
  end

  def test_datadog_per_request_span_with_retries
    set_datadog
    uri = URI(build_uri("/status/404", "http://#{httpbin}"))

    http = HTTPX.plugin(:retries, max_retries: 2, retry_on: ->(r) { r.status == 404 })
    response = http.get(uri)
    verify_status(response, 404)

    assert fetch_spans.size == 3, "expected to 3 spans"
    fetch_spans.each do |span|
      verify_instrumented_request(response.status, span: span, verb: "GET", uri: uri, error: "HTTPX::HTTPError")
    end
  end

  private

  def setup
    super
    Datadog.registry[:httpx].reset_configuration!
  end

  def teardown
    super
    Datadog.registry[:httpx].reset_configuration!
  end

  def datadog_service_name
    :httpx
  end

  def request_headers(response)
    request = response.instance_variable_get(:@request)
    request.headers
  end
end
