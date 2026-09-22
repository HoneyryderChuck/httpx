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
        Wrapper.new(*@tracers, *tracer.tracers)
      end

      def freeze
        @tracers.each(&:freeze).freeze
        super
      end

      %i[start finish reset enabled?].each do |callback|
        class_eval(<<-OUT, __FILE__, __LINE__ + 1)
          # proxies ##{callback} calls to wrapper tracers.
          def #{callback}(...)                        # def start(...)
            @tracers.each { |t| t.#{callback}(...) }  # @tracers.each { |t| t.start(....) }
          end                                         # end
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
      # time at which a request started being buffered for sending.
      attr_accessor :init_time

      # when not nil, it means this request was sent to a non-open connection, and contains how much time it took
      # the connection to connect.
      attr_accessor :handshake_time

      # intercepts request initialization to inject the tracing logic.
      def initialize(*)
        super

        @init_time = @handshake_time = nil

        tracer = @options.tracer

        return unless tracer && tracer.enabled?(self)

        on(:idle) do
          tracer.reset(self)

          # request is reset when it's retried.
          @init_time = @handshake_time = nil
        end
        on(:headers) do
          # the usual request init time (when not including the connection handshake)
          # should be the time the request is buffered the first time.
          @init_time = ::Time.now.utc
          @init_time -= @handshake_time if @handshake_time

          tracer.start(self)
        end
        on(:response) { |response| tracer.finish(self, response) }
      end

      def response=(*)
        # There are situations where connection initialization fails.
        # Example is the :ssrf_filter plugin, which raises an error on
        # initialize if the host is an IP which matches against the known set.
        # in such cases, we'll just set here right here.
        unless @init_time
          @init_time = ::Time.now.utc

          @init_time -= @handshake_time if @handshake_time
        end

        super
      end
    end

    # Connection mixin
    module ConnectionMethods
      def initialize(*)
        super

        @init_time = nil
      end

      def send_request_to_parser(request)
        if connecting? && @init_time
          # at this point, the connection has connected, but hasn't yet transitioned to :open,
          # so it's the time the requests which caused this connection to connect, are finally being
          # sent to the parser, so handshake time should factor into the span time.
          request.handshake_time ||= ::Time.now.utc - @init_time
        end

        super
      end

      def idling
        super

        @init_time = nil
      end

      def terminate
        super

        # ensure that connections which go back to the pool reset their init time.
        @init_time = nil
      end

      private

      def handle_error(er, request = nil)
        if connecting? && @init_time
          # bookkeep handshake time back into pending requests, which were never initialized with it.
          handshake_time = ::Time.now.utc - @init_time
          request.handshake_time ||= handshake_time if request
          @pending.each { |req| req.handshake_time ||= handshake_time }
        end

        super
      end

      def connect
        @init_time ||= ::Time.now.utc

        super
      end

      def ping(request)
        # if a connection is probed for liveness, the request timeframe should include
        # it too.
        request.init_time ||= ::Time.now.utc

        super
      end
    end

    module HTTP2Methods
      def initialize(*)
        super

        @handshake_time = nil
        @handshake_init_time = ::Time.now.utc
      end

      def send(request, head = false)
        if head
          # only true for pending requests waiting on the handshake, so handshake time accrues.
          request.handshake_time ||= 0.0
          request.handshake_time += @handshake_time
        end

        super
      end

      private

      def on_settings(*)
        @handshake_time = ::Time.now.utc - @handshake_init_time unless @handshake_completed

        super
      end
    end
  end
  register_plugin :tracing, Tracing
end
