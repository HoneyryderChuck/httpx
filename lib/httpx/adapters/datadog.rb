# frozen_string_literal: true

require "datadog/tracing/contrib/integration"
require "datadog/tracing/contrib/configuration/settings"
require "datadog/tracing/contrib/patcher"

module Datadog::Tracing
  module Contrib
    module HTTPX
      DATADOG_VERSION = defined?(::DDTrace) ? ::DDTrace::VERSION : ::Datadog::VERSION

      METADATA_MODULE = Datadog::Tracing::Metadata

      TYPE_OUTBOUND = Datadog::Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND

      TAG_PEER_SERVICE = Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE

      TAG_URL = Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL
      TAG_METHOD = Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD
      TAG_TARGET_HOST = Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST
      TAG_TARGET_PORT = Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT

      TAG_STATUS_CODE = Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE

      # HTTPX Datadog Plugin
      #
      # Enables tracing for httpx requests.
      #
      # A span will be created for each request transaction; the span is created lazily only when
      # receiving a response, and it is fed the start time stored inside the tracer object.
      #
      module Plugin
        class RequestTracer
          include Contrib::HttpAnnotationHelper

          SPAN_REQUEST = "httpx.request"

          # initializes the tracer object on the +request+.
          def initialize(request)
            @request = request
            @start_time = nil

            # request objects are reused, when already buffered requests get rerouted to a different
            # connection due to connection issues, or when they already got a response, but need to
            # be retried. In such situations, the original span needs to be extended for the former,
            # while a new is required for the latter.
            request.on(:idle) { reset }
            # the span is initialized when the request is buffered in the parser, which is the closest
            # one gets to actually sending the request.
            request.on(:headers) { call }
          end

          # sets up the span start time, while preparing the on response callback.
          def call(*args)
            return if @start_time

            start(*args)

            @request.once(:response, &method(:finish))
          end

          private

          # just sets the span init time. It can be passed a +start_time+ in cases where
          # this is collected outside the request transaction.
          def start(start_time = now)
            @start_time = start_time
          end

          # resets the start time for already finished request transactions.
          def reset
            return unless @start_time

            start
          end

          # creates the span from the collected +@start_time+ to what the +response+ state
          # contains. It also resets internal state to allow this object to be reused.
          def finish(response)
            return unless @start_time

            span = initialize_span

            return unless span

            if response.is_a?(::HTTPX::ErrorResponse)
              span.set_error(response.error)
            else
              span.set_tag(TAG_STATUS_CODE, response.status.to_s)

              span.set_error(::HTTPX::HTTPError.new(response)) if response.status >= 400 && response.status <= 599
            end

            span.finish
          ensure
            @start_time = nil
          end

          # return a span initialized with the +@request+ state.
          def initialize_span
            verb = @request.verb
            uri = @request.uri

            span = create_span(@request)

            span.resource = verb

            # Add additional request specific tags to the span.

            span.set_tag(TAG_URL, @request.path)
            span.set_tag(TAG_METHOD, verb)

            span.set_tag(TAG_TARGET_HOST, uri.host)
            span.set_tag(TAG_TARGET_PORT, uri.port.to_s)

            # Tag as an external peer service
            span.set_tag(TAG_PEER_SERVICE, span.service)

            if configuration[:distributed_tracing]
              propagate_trace_http(
                Datadog::Tracing.active_trace.to_digest,
                @request.headers
              )
            end

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            span
          rescue StandardError => e
            Datadog.logger.error("error preparing span for http request: #{e}")
            Datadog.logger.error(e.backtrace)
          end

          def now
            ::Datadog::Core::Utils::Time.now.utc
          end

          def configuration
            @configuration ||= Datadog.configuration.tracing[:httpx, @request.uri.host]
          end

          if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("2.0.0")
            def propagate_trace_http(digest, headers)
              Datadog::Tracing::Contrib::HTTP.inject(digest, headers)
            end

            def create_span(request)
              Datadog::Tracing.trace(
                SPAN_REQUEST,
                service: service_name(request.uri.host, configuration, Datadog.configuration_for(self)),
                type: TYPE_OUTBOUND,
                start_time: @start_time
              )
            end
          else
            def propagate_trace_http(digest, headers)
              Datadog::Tracing::Propagation::HTTP.inject!(digest, headers)
            end

            def create_span(request)
              Datadog::Tracing.trace(
                SPAN_REQUEST,
                service: service_name(request.uri.host, configuration, Datadog.configuration_for(self)),
                span_type: TYPE_OUTBOUND,
                start_time: @start_time
              )
            end
          end
        end

        module RequestMethods
          # intercepts request initialization to inject the tracing logic.
          def initialize(*)
            super

            return unless Datadog::Tracing.enabled?

            RequestTracer.new(self)
          end
        end

        module ConnectionMethods
          attr_reader :init_time

          def initialize(*)
            super

            @init_time = ::Datadog::Core::Utils::Time.now.utc
          end

          # handles the case when the +error+ happened during name resolution, which meanns
          # that the tracing logic hasn't been injected yet; in such cases, the approximate
          # initial resolving time is collected from the connection, and used as span start time,
          # and the tracing object in inserted before the on response callback is called.
          def handle_error(error)
            return super unless Datadog::Tracing.enabled?

            return super unless error.respond_to?(:connection)

            @pending.each do |request|
              RequestTracer.new(request).call(error.connection.init_time)
            end

            super
          end
        end
      end

      module Configuration
        # Default settings for httpx
        #
        class Settings < Datadog::Tracing::Contrib::Configuration::Settings
          DEFAULT_ERROR_HANDLER = lambda do |response|
            Datadog::Ext::HTTP::ERROR_RANGE.cover?(response.status)
          end

          option :service_name, default: "httpx"
          option :distributed_tracing, default: true
          option :split_by_domain, default: false

          if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.13.0")
            option :enabled do |o|
              o.type :bool
              o.env "DD_TRACE_HTTPX_ENABLED"
              o.default true
            end

            option :analytics_enabled do |o|
              o.type :bool
              o.env "DD_TRACE_HTTPX_ANALYTICS_ENABLED"
              o.default false
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env "DD_TRACE_HTTPX_ANALYTICS_SAMPLE_RATE"
              o.default 1.0
            end
          else
            option :enabled do |o|
              o.default { env_to_bool("DD_TRACE_HTTPX_ENABLED", true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(%w[DD_TRACE_HTTPX_ANALYTICS_ENABLED DD_HTTPX_ANALYTICS_ENABLED], false) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(%w[DD_TRACE_HTTPX_ANALYTICS_SAMPLE_RATE DD_HTTPX_ANALYTICS_SAMPLE_RATE], 1.0) }
              o.lazy
            end
          end

          if defined?(Datadog::Tracing::Contrib::SpanAttributeSchema)
            option :service_name do |o|
              o.default do
                Datadog::Tracing::Contrib::SpanAttributeSchema.fetch_service_name(
                  "DD_TRACE_HTTPX_SERVICE_NAME",
                  "httpx"
                )
              end
              o.lazy unless Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.13.0")
            end
          else
            option :service_name do |o|
              o.default do
                ENV.fetch("DD_TRACE_HTTPX_SERVICE_NAME", "httpx")
              end
              o.lazy unless Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.13.0")
            end
          end

          option :distributed_tracing, default: true

          if Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.15.0")
            option :error_handler do |o|
              o.type :proc
              o.default_proc(&DEFAULT_ERROR_HANDLER)
            end
          elsif Gem::Version.new(DATADOG_VERSION::STRING) >= Gem::Version.new("1.13.0")
            option :error_handler do |o|
              o.type :proc
              o.experimental_default_proc(&DEFAULT_ERROR_HANDLER)
            end
          else
            option :error_handler, default: DEFAULT_ERROR_HANDLER
          end
        end
      end

      # Patcher enables patching of 'httpx' with datadog components.
      #
      module Patcher
        include Datadog::Tracing::Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        # loads a session instannce with the datadog plugin, and replaces the
        # base HTTPX::Session with the patched session class.
        def patch
          datadog_session = ::HTTPX.plugin(Plugin)

          ::HTTPX.send(:remove_const, :Session)
          ::HTTPX.send(:const_set, :Session, datadog_session.class)
        end
      end

      # Datadog Integration for HTTPX.
      #
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new("0.10.2")

        register_as :httpx

        def self.version
          Gem.loaded_specs["httpx"] && Gem.loaded_specs["httpx"].version
        end

        def self.loaded?
          defined?(::HTTPX::Request)
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        def new_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
