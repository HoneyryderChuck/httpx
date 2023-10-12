# frozen_string_literal: true

if defined?(DDTrace) && DDTrace::VERSION::STRING >= "1.0.0"
  require "datadog/tracing/contrib/integration"
  require "datadog/tracing/contrib/configuration/settings"
  require "datadog/tracing/contrib/patcher"

  TRACING_MODULE = Datadog::Tracing
else

  require "ddtrace/contrib/integration"
  require "ddtrace/contrib/configuration/settings"
  require "ddtrace/contrib/patcher"

  TRACING_MODULE = Datadog
end

module TRACING_MODULE # rubocop:disable Naming/ClassAndModuleCamelCase
  module Contrib
    module HTTPX
      if defined?(::DDTrace) && ::DDTrace::VERSION::STRING >= "1.0.0"
        METADATA_MODULE = TRACING_MODULE::Metadata

        TYPE_OUTBOUND = TRACING_MODULE::Metadata::Ext::HTTP::TYPE_OUTBOUND

        TAG_PEER_SERVICE = TRACING_MODULE::Metadata::Ext::TAG_PEER_SERVICE

        TAG_URL = TRACING_MODULE::Metadata::Ext::HTTP::TAG_URL
        TAG_METHOD = TRACING_MODULE::Metadata::Ext::HTTP::TAG_METHOD
        TAG_TARGET_HOST = TRACING_MODULE::Metadata::Ext::NET::TAG_TARGET_HOST
        TAG_TARGET_PORT = TRACING_MODULE::Metadata::Ext::NET::TAG_TARGET_PORT

        TAG_STATUS_CODE = TRACING_MODULE::Metadata::Ext::HTTP::TAG_STATUS_CODE

      else

        METADATA_MODULE = Datadog

        TYPE_OUTBOUND = TRACING_MODULE::Ext::HTTP::TYPE_OUTBOUND
        TAG_PEER_SERVICE = TRACING_MODULE::Ext::Integration::TAG_PEER_SERVICE
        TAG_URL = TRACING_MODULE::Ext::HTTP::URL
        TAG_METHOD = TRACING_MODULE::Ext::HTTP::METHOD
        TAG_TARGET_HOST = TRACING_MODULE::Ext::NET::TARGET_HOST
        TAG_TARGET_PORT = TRACING_MODULE::Ext::NET::TARGET_PORT
        TAG_STATUS_CODE = Datadog::Ext::HTTP::STATUS_CODE
        PROPAGATOR = TRACING_MODULE::HTTPPropagator

      end

      # HTTPX Datadog Plugin
      #
      # Enables tracing for httpx requests. A span will be created for each individual requests,
      # and it'll trace since the moment it is fed to the connection, until the moment the response is
      # fed back to the session.
      #
      module Plugin
        class RequestTracer
          include Contrib::HttpAnnotationHelper

          SPAN_REQUEST = "httpx.request"

          def initialize(request)
            @request = request
          end

          def call
            return unless tracing_enabled?

            @request.on(:response, &method(:finish))

            verb = @request.verb
            uri = @request.uri

            @span = build_span

            @span.resource = verb

            # Add additional request specific tags to the span.

            @span.set_tag(TAG_URL, @request.path)
            @span.set_tag(TAG_METHOD, verb)

            @span.set_tag(TAG_TARGET_HOST, uri.host)
            @span.set_tag(TAG_TARGET_PORT, uri.port.to_s)

            # Tag as an external peer service
            @span.set_tag(TAG_PEER_SERVICE, @span.service)

            propagate_headers if @configuration[:distributed_tracing]

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(@configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(@span, @configuration[:analytics_sample_rate])
            end
          rescue StandardError => e
            Datadog.logger.error("error preparing span for http request: #{e}")
            Datadog.logger.error(e.backtrace)
          end

          def finish(response)
            return unless @span

            if response.is_a?(::HTTPX::ErrorResponse)
              @span.set_error(response.error)
            else
              @span.set_tag(TAG_STATUS_CODE, response.status.to_s)

              @span.set_error(::HTTPX::HTTPError.new(response)) if response.status >= 400 && response.status <= 599
            end

            @span.finish
          end

          private

          if defined?(::DDTrace) && ::DDTrace::VERSION::STRING >= "1.0.0"

            def build_span
              TRACING_MODULE.trace(
                SPAN_REQUEST,
                service: service_name(@request.uri.host, configuration, Datadog.configuration_for(self)),
                span_type: TYPE_OUTBOUND
              )
            end

            def propagate_headers
              TRACING_MODULE::Propagation::HTTP.inject!(TRACING_MODULE.active_trace, @request.headers)
            end

            def configuration
              @configuration ||= Datadog.configuration.tracing[:httpx, @request.uri.host]
            end

            def tracing_enabled?
              TRACING_MODULE.enabled?
            end
          else
            def build_span
              service_name = configuration[:split_by_domain] ? @request.uri.host : configuration[:service_name]
              configuration[:tracer].trace(
                SPAN_REQUEST,
                service: service_name,
                span_type: TYPE_OUTBOUND
              )
            end

            def propagate_headers
              Datadog::HTTPPropagator.inject!(@span.context, @request.headers)
            end

            def configuration
              @configuration ||= Datadog.configuration[:httpx, @request.uri.host]
            end

            def tracing_enabled?
              configuration[:tracer].enabled
            end
          end
        end

        module RequestMethods
          def __datadog_enable_trace!
            return if @__datadog_enable_trace

            RequestTracer.new(self).call
            @__datadog_enable_trace = true
          end
        end

        module ConnectionMethods
          def send(request)
            request.__datadog_enable_trace!

            super
          end
        end
      end

      module Configuration
        # Default settings for httpx
        #
        class Settings < TRACING_MODULE::Contrib::Configuration::Settings
          DEFAULT_ERROR_HANDLER = lambda do |response|
            Datadog::Ext::HTTP::ERROR_RANGE.cover?(response.status)
          end

          option :service_name, default: "httpx"
          option :distributed_tracing, default: true
          option :split_by_domain, default: false

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

          if defined?(TRACING_MODULE::Contrib::SpanAttributeSchema)
            option :service_name do |o|
              o.default do
                TRACING_MODULE::Contrib::SpanAttributeSchema.fetch_service_name(
                  "DD_TRACE_HTTPX_SERVICE_NAME",
                  "httpx"
                )
              end
              o.lazy
            end
          else
            option :service_name do |o|
              o.default do
                ENV.fetch("DD_TRACE_HTTPX_SERVICE_NAME", "httpx")
              end
              o.lazy
            end
          end

          option :distributed_tracing, default: true

          if DDTrace::VERSION::STRING >= "1.15.0"
            option :error_handler do |o|
              o.type :proc
              o.default_proc(&DEFAULT_ERROR_HANDLER)
            end
          else
            option :error_handler do |o|
              o.type :proc
              o.experimental_default_proc(&DEFAULT_ERROR_HANDLER)
            end
          end
        end
      end

      # Patcher enables patching of 'httpx' with datadog components.
      #
      module Patcher
        include TRACING_MODULE::Contrib::Patcher

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

        # MINIMUM_VERSION = Gem::Version.new('0.11.0')
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

        if defined?(::DDTrace) && ::DDTrace::VERSION::STRING >= "1.0.0"
          def new_configuration
            Configuration::Settings.new
          end
        else
          def default_configuration
            Configuration::Settings.new
          end
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
