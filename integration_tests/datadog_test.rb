# frozen_string_literal: true

require "ddtrace"
require "test_helper"
require "support/http_helpers"
require "httpx/adapters/datadog"

class DatadogTest < Minitest::Test
  include HTTPHelpers

  def test_datadog_successful_get_request
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, verb: "GET", uri: uri)
    verify_distributed_headers(response)
  end

  def test_datadog_successful_post_request
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.post(uri, body: "bla")
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, verb: "POST", uri: uri)
    verify_distributed_headers(response)
  end

  def test_datadog_successful_multiple_requests
    set_datadog
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    get_response, post_response = HTTPX.request([["GET", uri], ["POST", uri]])
    verify_status(get_response, 200)
    verify_status(post_response, 200)

    assert fetch_spans.size == 2, "expected to have 2 spans"
    get_span, post_span = fetch_spans
    verify_instrumented_request(get_response, span: get_span, verb: "GET", uri: uri)
    verify_instrumented_request(post_response, span: post_span, verb: "POST", uri: uri)
    verify_distributed_headers(get_response, span: get_span)
    verify_distributed_headers(post_response, span: post_span)
    verify_analytics_headers(get_span)
    verify_analytics_headers(post_span)
  end

  def test_datadog_server_error_request
    set_datadog
    uri = URI(build_uri("/status/500", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 500)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, verb: "GET", uri: uri)
    verify_distributed_headers(response)
  end

  def test_datadog_client_error_request
    set_datadog
    uri = URI(build_uri("/status/404", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 404)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, verb: "GET", uri: uri)
    verify_distributed_headers(response)
  end

  def test_datadog_some_other_error
    set_datadog
    uri = URI("http://unexisting/")

    response = HTTPX.get(uri)
    assert response.is_a?(HTTPX::ErrorResponse), "response should contain errors"

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, verb: "GET", uri: uri, error: "HTTPX::NativeResolveError")
    verify_distributed_headers(response)
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
    verify_instrumented_request(response, service: "httpbin", verb: "GET", uri: uri)
    verify_distributed_headers(response)
  end

  def test_datadog_split_by_domain
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))
    set_datadog do |http|
      http.split_by_domain = true
    end

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, service: uri.host, verb: "GET", uri: uri)
    verify_distributed_headers(response)
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
    verify_instrumented_request(response, span: span, verb: "GET", uri: uri)
    verify_no_distributed_headers(response)
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
    verify_instrumented_request(response, span: span, verb: "GET", uri: uri)
    verify_distributed_headers(response, span: span, sampling_priority: sampling_priority)
    verify_analytics_headers(span)
  end

  def test_datadog_analytics_enabled
    set_datadog(analytics_enabled: true)
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response, span: span, verb: "GET", uri: uri)
    verify_analytics_headers(span, sample_rate: 1.0)
  end

  def test_datadog_analytics_sample_rate
    set_datadog(analytics_enabled: true, analytics_sample_rate: 0.5)
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)
    verify_status(response, 200)

    assert !fetch_spans.empty?, "expected to have spans"
    span = fetch_spans.last
    verify_instrumented_request(response, span: span, verb: "GET", uri: uri)
    verify_analytics_headers(span, sample_rate: 0.5)
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

  def verify_instrumented_request(response, verb:, uri:, span: fetch_spans.first, service: "httpx", error: nil)
    assert span.span_type == "http"
    assert span.name == "httpx.request"
    assert span.service == service

    assert span.get_tag("out.host") == uri.host
    assert span.get_tag("out.port") == "80"
    assert span.get_tag("http.method") == verb
    assert span.get_tag("http.url") == uri.path

    error_tag = if defined?(::DDTrace) && Gem::Version.new(::DDTrace::VERSION::STRING) >= Gem::Version.new("1.8.0")
      "error.message"
    else
      "error.msg"
    end

    if error
      assert span.get_tag("error.type") == "HTTPX::NativeResolveError"
      assert !span.get_tag(error_tag).nil?
      assert span.status == 1
    elsif response.status >= 400
      assert span.get_tag("http.status_code") == response.status.to_s
      assert span.get_tag("error.type") == "HTTPX::HTTPError"
      assert !span.get_tag(error_tag).nil?
      assert span.status == 1
    else
      assert span.status.zero?
      assert span.get_tag("http.status_code") == response.status.to_s
      # peer service
      assert span.get_tag("peer.service") == span.service
    end
  end

  def verify_no_distributed_headers(response)
    request = response.instance_variable_get(:@request)

    assert !request.headers.key?("x-datadog-parent-id")
    assert !request.headers.key?("x-datadog-trace-id")
    assert !request.headers.key?("x-datadog-sampling-priority")
  end

  def verify_distributed_headers(response, span: fetch_spans.first, sampling_priority: 1)
    request = response.instance_variable_get(:@request)

    assert request.headers["x-datadog-parent-id"] == span.span_id.to_s
    assert request.headers["x-datadog-trace-id"] == trace_id(span)
    assert request.headers["x-datadog-sampling-priority"] == sampling_priority.to_s
  end


  if defined?(::DDTrace) && Gem::Version.new(::DDTrace::VERSION::STRING) >= Gem::Version.new("1.17.0")
    def trace_id(span)
      Datadog::Tracing::Utils::TraceId.to_low_order(span.trace_id).to_s
    end
  else
    def trace_id(span)
      span.trace_id.to_s
    end
  end


  def verify_analytics_headers(span, sample_rate: nil)
    assert span.get_metric("_dd1.sr.eausr") == sample_rate
  end

  def set_datadog(options = {}, &blk)
    Datadog.configure do |c|
      c.tracing.instrument(:httpx, options, &blk)
    end

    tracer # initialize tracer patches
  end

  def tracer
    @tracer ||= begin
      tr =  Datadog::Tracing.send(:tracer)
      def tr.write(trace)
        @traces ||= []
        @traces << trace
      end
      tr
    end
  end

  def trace_with_sampling_priority(priority)
    tracer.trace("foo.bar") do
      tracer.active_trace.sampling_priority = priority
      yield
    end
  end

  # Returns spans and caches it (similar to +let(:spans)+).
  def spans
    @spans ||= fetch_spans
  end

  # Retrieves and sorts all spans in the current tracer instance.
  # This method does not cache its results.
  def fetch_spans
    spans = (tracer.instance_variable_get(:@traces) || []).map(&:spans)
    spans.flatten.sort! do |a, b|
      if a.name == b.name
        if a.resource == b.resource
          if a.start_time == b.start_time
            a.end_time <=> b.end_time
          else
            a.start_time <=> b.start_time
          end
        else
          a.resource <=> b.resource
        end
      else
        a.name <=> b.name
      end
    end
  end
end
