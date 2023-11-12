# frozen_string_literal: true

require "sentry-ruby"

module HTTPX::Plugins
  module Sentry
    module Tracer
      module_function

      def call(request)
        sentry_span = start_sentry_span

        return unless sentry_span

        set_sentry_trace_header(request, sentry_span)

        request.on(:response, &method(:finish_sentry_span).curry(3)[sentry_span, request])
      end

      def start_sentry_span
        return unless ::Sentry.initialized? && (span = ::Sentry.get_current_scope.get_span)
        return if span.sampled == false

        span.start_child(op: "httpx.client", start_timestamp: ::Sentry.utc_now.to_f)
      end

      def set_sentry_trace_header(request, sentry_span)
        return unless sentry_span

        config = ::Sentry.configuration
        url = request.uri.to_s

        return unless config.propagate_traces && config.trace_propagation_targets.any? { |target| url.match?(target) }

        trace = ::Sentry.get_current_client.generate_sentry_trace(sentry_span)
        request.headers[::Sentry::SENTRY_TRACE_HEADER_NAME] = trace if trace
      end

      def finish_sentry_span(span, request, response)
        return unless ::Sentry.initialized?

        record_sentry_breadcrumb(request, response)
        record_sentry_span(request, response, span)
      end

      def record_sentry_breadcrumb(req, res)
        return unless ::Sentry.configuration.breadcrumbs_logger.include?(:http_logger)

        request_info = extract_request_info(req)

        data = if res.is_a?(HTTPX::ErrorResponse)
          { error: res.error.message, **request_info }
        else
          { status: res.status, **request_info }
        end

        crumb = ::Sentry::Breadcrumb.new(
          level: :info,
          category: "httpx",
          type: :info,
          data: data
        )
        ::Sentry.add_breadcrumb(crumb)
      end

      def record_sentry_span(req, res, sentry_span)
        return unless sentry_span

        request_info = extract_request_info(req)
        sentry_span.set_description("#{request_info[:method]} #{request_info[:url]}")
        if res.is_a?(HTTPX::ErrorResponse)
          sentry_span.set_data(:error, res.error.message)
        else
          sentry_span.set_data(:status, res.status)
        end
        sentry_span.set_timestamp(::Sentry.utc_now.to_f)
      end

      def extract_request_info(req)
        uri = req.uri

        result = {
          method: req.verb,
        }

        if ::Sentry.configuration.send_default_pii
          uri += "?#{req.query}" unless req.query.empty?
          result[:body] = req.body.to_s unless req.body.empty? || req.body.unbounded_body?
        end

        result[:url] = uri.to_s

        result
      end
    end

    module RequestMethods
      def __sentry_enable_trace!
        return if @__sentry_enable_trace

        Tracer.call(self)
        @__sentry_enable_trace = true
      end
    end

    module ConnectionMethods
      def send(request)
        request.__sentry_enable_trace!

        super
      end
    end
  end
end

Sentry.register_patch(:httpx) do
  sentry_session = HTTPX.plugin(HTTPX::Plugins::Sentry)

  HTTPX.send(:remove_const, :Session)
  HTTPX.send(:const_set, :Session, sentry_session.class)
end
