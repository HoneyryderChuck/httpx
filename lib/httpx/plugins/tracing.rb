# frozen_string_literal: true

module HTTPX::Plugins
  #
  # This plugin adds a simple interface to integrate request tracing SDKs.
  #
  # An example of such an integration is the datadog adapter.
  #
  # https://gitlab.com/os85/httpx/wikis/Tracing
  #
  module Tracing
    class Wrapper
      attr_reader :tracers
      protected :tracers

      def initialize(*tracers)
        @tracers = tracers.flat_map do |tracer|
          case tracer
          when Wrapper
            tracer.tracers
          else
            tracer
          end
        end.uniq
      end

      def merge(tracer)
        case tracer
        when Wrapper
          Wrapper.new(*@tracers, *tracer.tracers)
        else
          Wrapper.new(*@tracers, tracer)
        end
      end

      def freeze
        @tracers.each(&:freeze).freeze
        super
      end

      %i[start finish reset enabled?].each do |callback|
        class_eval(<<-OUT, __FILE__, __LINE__ + 1)
          # proxies ##{callback} calls to wrapper tracers.
          def #{callback}(*args)                        # def start(*args)
            @tracers.each { |t| t.#{callback}(*args) }  # @tracers.each { |t| t.start(*args) }
          end                                           # end
        OUT
      end
    end

    # adds support for the following options:
    #
    # :tracer :: object which responds to #start, #finish and #reset.
    module OptionsMethods
      private

      def option_tracer(tracer)
        unless tracer.respond_to?(:start) &&
               tracer.respond_to?(:finish) &&
               tracer.respond_to?(:reset) &&
               tracer.respond_to?(:enabled?)
          raise TypeError, "#{tracer} must to respond to `#start(r)`, `#finish` and `#reset` and `#enabled?"
        end

        tracer = Wrapper.new(@tracer, tracer) if @tracer
        tracer
      end
    end

    module RequestMethods
      attr_accessor :init_time

      # intercepts request initialization to inject the tracing logic.
      def initialize(*)
        super

        @init_time = nil

        tracer = @options.tracer

        return unless tracer && tracer.enabled?(self)

        on(:idle) do
          tracer.reset(self)

          # request is reset when it's retried.
          @init_time = nil
        end
        on(:headers) do
          # the usual request init time (when not including the connection handshake)
          # should be the time the request is buffered the first time.
          @init_time ||= ::Time.now.utc

          tracer.start(self)
        end
        on(:response) { |response| tracer.finish(self, response) }
      end

      def response=(*)
        # init_time should be set when it's send to a connection.
        # However, there are situations where connection initialization fails.
        # Example is the :ssrf_filter plugin, which raises an error on
        # initialize if the host is an IP which matches against the known set.
        # in such cases, we'll just set here right here.
        @init_time ||= ::Time.now.utc

        super
      end
    end

    # Connection mixin
    module ConnectionMethods
      def initialize(*)
        super

        @init_time = ::Time.now.utc
      end

      def send(request)
        # request init time is only the same as the connection init time
        # if the connection is going through the connection handshake.
        request.init_time ||= @init_time unless open?

        super
      end

      def idling
        super

        # time of initial request(s) is accounted from the moment
        # the connection is back to :idle, and ready to connect again.
        @init_time = ::Time.now.utc
      end
    end
  end
  register_plugin :tracing, Tracing
end
