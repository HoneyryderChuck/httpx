# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for request hedging, i.e. a latency-mitigation strategy that involves
    # sending requests through multiple connections and returning the fastest response.
    #
    # https://gitlab.com/os85/httpx/wikis/Hedging#hedging
    #
    module Hedging
      # :hedge_after:: seconds after which, if the request didn't complete yet, it'll be sent on a different connection
      module OptionsMethods
        private

        def option_hedge_after(value)
          if value.respond_to?(:call)
            value1 = value
            value1 = value1.method(:call) unless value1.respond_to?(:arity)

            # allow ->(*) arity as well, which is < 0
            raise TypeError, "`:hedge_after` proc has invalid number of parameters" unless value1.arity.negative? || value1.arity.between?(
              1, 2
            )

          else
            value = Float(value)
            raise TypeError, "`:hedge_after` must be positive" unless value.positive?
          end

          value
        end
      end

      module InstanceMethods
        def select_connection(connection, selector)
          connection.try_yield_hedge_connection do |hedge_conn|
            super.tap do
              select_connection(hedge_conn, selector) if hedge_conn
            end
          end
        end

        private

        def do_request(request, connection, selector)
          super.tap do
            # forego hedging if the connection is already open, or if
            # the connection is scheduled for DNS resolution, as pending requests
            # will be hedged afterwards.
            next if connection.open? || !connection.addresses?

            hedge_request!(request, connection, selector)
          end
        end

        # creates the hedge connection before a connection initiates the connection handshake.
        # This excludes connections which are already open.
        def on_resolver_connection(connection, selector)
          super.tap do
            next if connection.open? || connection.hedge_connection

            connection.pending.each do |request|
              hedge_request!(request, connection, selector)
            end

            on_resolver_connection(connection.hedge_connection, selector) if connection.hedge_connection
          end
        end

        def hedge_connection(connection)
          connection.hedge_connection || begin
            new_connection = connection.dup
            new_connection.log { "cloning hedge connection of connection##{connection.object_id}..." }
            connection.hedge_connection = new_connection
            new_connection
          end
        end

        def hedge_request!(request, connection, selector)
          hedge_after = when_to_hedge(request)

          if hedge_after&.positive?
            # hedge after interval
            cb = selector.after(hedge_after) do
              next if request.response

              request.hedge_request = hedge_request = request.dup
              hedge_conn = hedge_connection(connection)
              hedge_conn.send(hedge_request)
              select_connection(hedge_conn, selector)
            end

            # forego hedging if request is over
            request.once(:response) do
              cb.cancel
            end
          else
            request.hedge_request = hedge_request = request.dup
            hedge_connection(connection).send(hedge_request)
          end
        end

        def when_to_hedge(request)
          hedge_after = request.options.hedge_after

          return unless hedge_after

          hedge_after = hedge_after.call(request) if hedge_after.respond_to?(:call)

          hedge_after
        end

        # hedge connections should not deactivate, instead they should terminate.
        # this ensures that persistent hedge connections aren't treated as persistent,
        # and close instead of deactivating.
        def deactivate(selector, *)
          hedge_connections = selector.each_connection.select(&:is_hedge_connection)

          return super unless hedge_connections.any?

          selector_close(selector, hedge_connections)

          super
        end

        # do not check hedge connections back in
        def can_checkin?(connection)
          super && !connection.is_hedge_connection
        end
      end

      module RequestMethods
        # TODO: would be nice to get rid of this
        attr_reader :connection

        attr_reader :hedge_request

        def initialize(*)
          super
          @is_hedge_request = false
        end

        def hedge_request=(request)
          @hedge_request = request

          return unless request

          @is_hedge_request = !request.hedge_request.nil?

          return if @is_hedge_request

          request.hedge_request = self
        end

        def response=(response)
          return super unless @hedge_request # rubocop:disable Lint/ReturnInVoidContext

          prev_response = @response

          begin
            super
          ensure
            @response = prev_response if prev_response
          end
        end

        def emit_response(response)
          hedge_request = @hedge_request

          return super unless hedge_request

          return super unless hedge_request &&
                              (
                                hedge_request.response.nil? ||
                                !hedge_request.response.finished?
                              )

          # if this response is for a hedge request, and the main request
          # didn't complete yet, then we replace it.

          super.tap do
            hedge_request.response = response

            # should cancel any pending HTTP/2 stream; there's no way to
            # cancel an HTTP/1 request, so that one will run to completion.
            hedge_request.emit(:refuse)
          end
        ensure
          self.hedge_request = nil
        end
      end

      module ResponseMethods
        def finish!
          connection = @request.connection

          super

          return unless connection && (hedge_connection = connection.hedge_connection)

          # disconnect connection with its hedge, so that objects do not leak after
          # they're not needed.
          connection.hedge_connection = hedge_connection.hedge_connection = nil

          # remarking itself as the main connection, so that it's not discarded when
          # going back to the pool.
          connection.is_hedge_connection = false
          hedge_connection.is_hedge_connection = true
        end
      end

      module ConnectionMethods
        attr_reader :hedge_connection

        attr_accessor :is_hedge_connection

        def initialize(*)
          super
          @is_hedge_connection = false
        end

        def addresses=(addrs)
          try_yield_hedge_connection do |hedge_conn|
            super.tap do
              hedge_conn.addresses = addrs if hedge_conn
            end
          end
        end

        def hedge_connection=(connection)
          @hedge_connection = connection

          return unless connection

          @is_hedge_connection = !connection.hedge_connection.nil?

          return if @is_hedge_connection

          connection.hedge_connection = self
        end

        def try_yield_hedge_connection
          return yield(nil) unless (hedge_conn = @hedge_connection)

          @hedge_connection = nil

          begin
            hedge_conn.try_yield_hedge_connection do
              yield(hedge_conn)
            end
          ensure
            @hedge_connection = hedge_conn
          end
        end

        # connections should not merge with their hedge connections
        def mergeable?(connection)
          super && connection.hedge_connection != self
        end

        def send(request)
          super.tap do
            if @hedge_connection && !request.hedge_request
              request.hedge_request = hedge_request = request.dup
              @hedge_connection.send(hedge_request)
            end
          end
        end

        private

        def send_request_to_parser(request, *)
          # if original request was in the queue, but has since been finished
          # in the hedge connection.
          return false if request.response&.finished?

          super
        end
      end
    end
    register_plugin(:hedging, Hedging)
  end
end
