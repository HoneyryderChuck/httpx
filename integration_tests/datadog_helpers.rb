# frozen_string_literal: true

module DatadogHelpers
  DATADOG_VERSION = defined?(DDTrace) ? DDTrace::VERSION : Datadog::VERSION

  private

  def verify_instrumented_request(status, verb:, uri:, span: fetch_spans.first, service: datadog_service_name.to_s, error: nil)
    if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("2.0.0")
      assert span.type == "http"
    else
      assert span.span_type == "http"
    end
    assert span.name == "#{datadog_service_name}.request"
    assert span.service == service

    assert span.get_tag("out.host") == uri.host
    assert span.get_tag("out.port") == 80
    assert span.get_tag("http.method") == verb
    assert span.get_tag("http.url") == uri.path

    error_tag = if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.8.0")
      "error.message"
    else
      "error.msg"
    end

    if status && status >= 400
      assert span.get_tag("http.status_code") == status.to_s
      assert span.get_tag("error.type") == error # "Error #{status}"
      # assert !span.get_tag(error_tag).nil?
      assert span.status == 1
    elsif error
      assert span.get_tag("error.type") == "HTTPX::NativeResolveError"
      assert !span.get_tag(error_tag).nil?
      assert span.status == 1
    else
      assert span.status.zero?
      assert span.get_tag("http.status_code") == status.to_s
      # peer service
      # assert span.get_tag("peer.service") == span.service
    end
  end

  def verify_no_distributed_headers(request_headers)
    assert !request_headers.key?("x-datadog-parent-id")
    assert !request_headers.key?("x-datadog-trace-id")
    assert !request_headers.key?("x-datadog-sampling-priority")
  end

  def verify_distributed_headers(request_headers, span: fetch_spans.first, sampling_priority: 1)
    if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("2.0.0")
      assert request_headers["x-datadog-parent-id"] == span.id.to_s
    else
      assert request_headers["x-datadog-parent-id"] == span.span_id.to_s
    end
    assert request_headers["x-datadog-trace-id"] == trace_id(span)
    assert request_headers["x-datadog-sampling-priority"] == sampling_priority.to_s
  end

  if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.17.0")
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
      c.tracing.instrument(datadog_service_name, options, &blk)
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
