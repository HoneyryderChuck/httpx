# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "ddtrace"
require "httpx/adapters/datadog"

class DatadogTest < Minitest::Test
  include HTTPHelpers

  def setup
    configuration_options = {}
    Datadog.configure do |c|
      c.use :httpx, configuration_options
    end
    Datadog.reset!
    Datadog.registry[:httpx].reset_configuration!

    tracer # initialize tracer patches
  end

  def test_datadog_successful_request
    uri = URI(build_uri("/status/200", "http://#{httpbin}"))

    response = HTTPX.get(uri)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, meth: "GET", uri: uri, status: 200)
  end

  def test_datadog_server_error_request
    uri = URI(build_uri("/status/500", "http://#{httpbin}"))

    response = HTTPX.get(uri)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, meth: "GET", uri: uri, status: 500)
    span = fetch_spans.first
    assert span.get_tag("error.type") == "HTTPX::HTTPError"
  end

  def test_datadog_client_error_request
    uri = URI(build_uri("/status/404", "http://#{httpbin}"))

    response = HTTPX.get(uri)

    assert !fetch_spans.empty?, "expected to have spans"
    verify_instrumented_request(response, meth: "GET", uri: uri, status: 404)
    span = fetch_spans.first
    assert span.get_tag("error.type") == "HTTPX::HTTPError"
  end

  private

  def verify_instrumented_request(response, meth:, uri:, status:)
    assert response.status == status
    assert fetch_spans.first.is_a?(Datadog::Span)
    span = fetch_spans.first
    assert span.get_tag(Datadog::Ext::NET::TARGET_HOST) == uri.host
    assert span.get_tag(Datadog::Ext::NET::TARGET_PORT) == "80"
    assert span.get_tag(Datadog::Ext::HTTP::METHOD) == meth
    assert span.get_tag(Datadog::Ext::HTTP::URL) == uri.path
    assert span.get_tag(Datadog::Ext::HTTP::STATUS_CODE) == status.to_s
    assert span.span_type == "http"
    assert span.name == "httpx.request"
    assert span.service == "httpx"
    # peer service
    assert span.get_tag("peer.service") == span.service
    verify_propagates_headers(span, response)
  end

  def verify_propagates_headers(span, response)
    distributed_tracing_headers = { "X-Datadog-Parent-Id" => span.span_id.to_s,
                                    "X-Datadog-Trace-Id" => span.trace_id.to_s }

    request = response.instance_variable_get(:@request)
    distributed_tracing_headers.each do |field, value|
      assert request.headers[field] == value
    end
  end

  def tracer
    @tracer ||= begin
      tr = Datadog.tracer
      def tr.write(trace)
        @spans ||= []
        @spans << trace
      end
      tr
    end
  end

  # Returns spans and caches it (similar to +let(:spans)+).
  def spans
    @spans ||= fetch_spans
  end

  # Retrieves and sorts all spans in the current tracer instance.
  # This method does not cache its results.
  def fetch_spans
    spans = tracer.instance_variable_get(:@spans) || []
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

  #   context 'distributed tracing disabled' do
  #     let(:configuration_options) { super().merge(distributed_tracing: false) }

  #     it_behaves_like 'instrumented request'

  #     shared_examples_for 'does not propagate distributed headers' do
  #       it 'does not propagate the headers' do
  #         request

  #         distributed_tracing_headers = { 'X-Datadog-Parent-Id' => span.span_id.to_s,
  #                                         'X-Datadog-Trace-Id' => span.trace_id.to_s }

  #         expect(a_request(:get, url).with(headers: distributed_tracing_headers)).to_not have_been_made
  #       end
  #     end

  #     it_behaves_like 'does not propagate distributed headers'

  #     context 'with sampling priority' do
  #       let(:sampling_priority) { 0.2 }

  #       before do
  #         tracer.provider.context.sampling_priority = sampling_priority
  #       end

  #       it_behaves_like 'does not propagate distributed headers'

  #       it 'does not propagate sampling priority headers' do
  #         RestClient.get(url)

  #         expect(a_request(:get, url).with(headers: { 'X-Datadog-Sampling-Priority' => sampling_priority.to_s }))
  #           .to_not have_been_made
  #       end
  #     end
  #   end
  # end
end
