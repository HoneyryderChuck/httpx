# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds suppoort for callbacks around the request/response lifecycle.
    #
    # https://gitlab.com/os85/httpx/-/wikis/Events
    #
    module Callbacks
      CALLBACKS = %i[
        connection_opened connection_closed
        request_error
        request_started request_body_chunk request_completed
        response_started response_body_chunk response_completed
      ].freeze

      # connection closed user-space errors happen after errors can be surfaced to requests,
      # so they need to pierce through the scheduler, which is only possible by simulating an
      # interrupt.
      class CallbackError < Exception; end # rubocop:disable Lint/InheritException

      module InstanceMethods
        include HTTPX::Callbacks

        CALLBACKS.each do |meth|
          class_eval(<<-MOD, __FILE__, __LINE__ + 1)
            # sets a <tt>:#{meth}</tt> callback on the session
            def on_#{meth}(&blk)   # def on_connection_opened(&blk)
              on(:#{meth}, &blk)   #   on(:connection_opened, &blk)
              self                 #   self
            end                    # end
          MOD
        end

        def plugin(*args, &blk)
          # ruby 2.7 requires explicit named splat
          super(*args).tap do |sess|
            CALLBACKS.each do |cb|
              next unless callbacks_for?(cb)

              sess.callbacks(cb).concat(callbacks(cb))
            end

            sess.wrap(&blk) if blk
          end
        end

        def close(*)
          super
        rescue CallbackError => e
          raise e.cause
        end

        private

        def branch(options, &blk)
          super(options).tap do |sess|
            CALLBACKS.each do |cb|
              next unless callbacks_for?(cb)

              sess.callbacks(cb).concat(callbacks(cb))
            end
            sess.wrap(&blk) if blk
          end
        end

        def do_init_connection(connection, selector)
          super
          connection.on(:open) do
            next unless connection.current_session == self

            emit_or_callback_error(:connection_opened, connection.origin, connection.io.socket, connection: connection)
          end
          connection.on(:callback_connection_closed) do |previous_session, error|
            next unless previous_session == self

            emit_or_callback_error(:connection_closed, connection.origin, error, connection: connection) if connection.used?
          end

          connection
        end

        def set_request_callbacks(request)
          super

          request.on(:headers) do
            emit_or_callback_error(:request_started, request, connection: request.connection)
          end
          request.on(:body_chunk) do |chunk|
            emit_or_callback_error(:request_body_chunk, request, chunk, connection: request.connection)
          end
          request.on(:done) do
            emit_or_callback_error(:request_completed, request, connection: request.connection)
          end

          request.on(:response_started) do |res|
            # .last_connection happens when an error happens before the request is prepared to be sent,
            # i.e. when connecting fails.
            connection = request.connection || request.last_connection
            if res.is_a?(Response)
              emit_or_callback_error(:response_started, request, res, connection: connection)
              res.on(:chunk_received) do |chunk|
                emit_or_callback_error(:response_body_chunk, request, res, chunk, connection: connection)
              end
            else
              emit_or_callback_error(:request_error, request, res.error, connection: connection)
            end
          end
          request.on(:response_completed) do |res|
            emit_or_callback_error(:response_completed, request, res, connection: request.connection)
          end
        end

        def emit_or_callback_error(...)
          emit(...)
        rescue StandardError => e
          ex = CallbackError.new(e.message)
          ex.set_backtrace(e.backtrace)
          raise ex
        end

        def receive_requests(*)
          super
        rescue CallbackError => e
          raise e.cause
        end
      end

      module RequestMethods
        # allows getting the connection that the request was sent over
        attr_reader :connection

        # gets the failed connection the request was supposed to be sent over
        attr_accessor :last_connection

        def drain_body
          super.tap do |chunk|
            emit(:body_chunk, chunk) if chunk
          rescue StandardError => e
            # in case an error occurs in callback code
            @drain_error = e
            nil
          end
        end
      end

      module ResponseMethods
        def finish!
          # emit before connection is unassigned
          @request.emit(:response_completed, self)

          super
        end
      end

      module ConnectionMethods
        def initialize(*)
          super
          @last_error = nil
        end

        def on_connect_error(e)
          with_last_error(e) do
            super
          end
        end

        def on_error(e, request = nil)
          with_current_connection(request) do
            with_last_error(e) do
              super
            end
          end
        end

        private

        def on_parser_error(request, _)
          with_current_connection(request) do
            super
          end
        end

        def with_current_connection(request)
          return yield unless request

          begin
            prev_conn = request.connection
            request.connection = self
            request.last_connection = self
            yield
          ensure
            request.connection = prev_conn if request.connection == self
            request.last_connection = nil
          end
        end

        def with_last_error(e)
          @last_error = e
          yield
        ensure
          @last_error = nil if @last_error == e
        end

        def disconnect
          session = @current_session
          super.tap do |was_closed|
            emit(:callback_connection_closed, session, @last_error) if was_closed
          end
        end
      end
    end
    register_plugin :callbacks, Callbacks
  end
end
