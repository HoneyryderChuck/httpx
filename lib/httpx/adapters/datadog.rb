# frozen_string_literal: true

require "ddtrace/contrib/integration"
require "ddtrace/contrib/rest_client/configuration/settings"
require "ddtrace/contrib/rest_client/patcher"

module Datadog
  module Contrib
    module HTTPX
      # HTTPX Datadog Plugin
      #
      # Enables tracing for httpx requests. A span will be created for each individual requests,
      # and it'll trace since the moment it is fed to the connection, until the moment the response is
      # fed back to the session.
      #
      module Plugin
        module ConnectionMethods
          def send(request)
            request.start_trace!
            super
          end
        end

        module RequestMethods
          SPAN_REQUEST = "httpx.request"

          def start_trace!
            return if skip_tracing?

            on(:response, &method(:finish_trace!))

            @span = datadog_pin.tracer.trace(SPAN_REQUEST)
            service_name = datadog_config[:split_by_domain] ? uri.host : datadog_pin.service_name

            begin
              @span.service = service_name
              @span.span_type = Datadog::Ext::HTTP::TYPE_OUTBOUND
              @span.resource = verb.to_s.upcase

              Datadog::HTTPPropagator.inject!(@span.context, @headers) if datadog_pin.tracer.enabled && !skip_distributed_tracing?

              # Add additional request specific tags to the span.

              @span.set_tag(Datadog::Ext::HTTP::URL, path)
              @span.set_tag(Datadog::Ext::HTTP::METHOD, verb.to_s.upcase)

              @span.set_tag(Datadog::Ext::NET::TARGET_HOST, uri.host)
              @span.set_tag(Datadog::Ext::NET::TARGET_PORT, uri.port.to_s)

              # Tag as an external peer service
              @span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, @span.service)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(datadog_config[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(@span, datadog_config[:analytics_sample_rate])
              end
            rescue StandardError => e
              Datadog.logger.error("error preparing span for http request: #{e}")
            end
          rescue StandardError => e
            Datadog.logger.debug("Failed to start span: #{e}")
          end

          def finish_trace!(response)
            return unless @span

            if response.respond_to?(:error)
              @span.set_error(response.error)
            else
              @span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, response.status.to_s)

              @span.set_error(::HTTPX::HTTPError.new(response)) if response.status >= 400 && response.status <= 599
            end

            @span.finish
          end

          private

          def skip_tracing?
            return true if @headers.key?(Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION)

            return false unless @datadog_pin

            span = @datadog_pin.tracer.active_span

            return true if span && (span.name == SPAN_REQUEST)

            false
          end

          def skip_distributed_tracing?
            return !datadog_pin.config[:distributed_tracing] if datadog_pin.config && datadog_pin.config.key?(:distributed_tracing)

            !Datadog.configuration[:httpx][:distributed_tracing]
          end

          def datadog_pin
            @datadog_pin ||= begin
              service = datadog_config[:service_name]
              tracer = datadog_config[:tracer]

              Datadog::Pin.new(
                service,
                app: "httpx",
                app_type: Datadog::Ext::AppTypes::WEB,
                tracer: -> { tracer }
              )
            end
          end

          def datadog_config
            @datadog_config ||= Datadog.configuration[:httpx, @uri.host]
          end
        end
      end

      module Configuration
        # Default settings for httpx
        #
        class Settings < Datadog::Contrib::Configuration::Settings
          option :service_name, default: "httpx"
          option :distributed_tracing, default: true
          option :split_by_domain, default: false

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

          option :error_handler, default: Datadog::Tracer::DEFAULT_ON_ERROR
        end
      end

      # Patcher enables patching of 'httpx' with datadog components.
      #
      module Patcher
        include Datadog::Contrib::Patcher

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

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
