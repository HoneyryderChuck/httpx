# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds suppoort for callbacks around the request/response lifecycle.
    #
    # https://gitlab.com/os85/httpx/-/wikis/Events
    #
    module Callbacks
      # connection closed user-space errors happen after errors can be surfaced to requests,
      # so they need to pierce through the scheduler, which is only possible by simulating an
      # interrupt.
      class CallbackError < Exception; end # rubocop:disable Lint/InheritException

      module InstanceMethods
        include HTTPX::Callbacks

        %i[
          connection_opened connection_closed
          request_error
          request_started request_body_chunk request_completed
          response_started response_body_chunk response_completed
        ].each do |meth|
          class_eval(<<-MOD, __FILE__, __LINE__ + 1)
            def on_#{meth}(&blk)   # def on_connection_opened(&blk)
              on(:#{meth}, &blk)   #   on(:connection_opened, &blk)
              self                 #   self
            end                    # end
          MOD
        end

        private

        def do_init_connection(connection, selector)
          super
          connection.on(:open) do
            next unless connection.current_session == self

            emit_or_callback_error(:connection_opened, connection.origin, connection.io.socket)
          end
          connection.on(:close) do
            next unless connection.current_session == self

            emit_or_callback_error(:connection_closed, connection.origin) if connection.used?
          end

          connection
        end

        def set_request_callbacks(request)
          super

          request.on(:headers) do
            emit_or_callback_error(:request_started, request)
          end
          request.on(:body_chunk) do |chunk|
            emit_or_callback_error(:request_body_chunk, request, chunk)
          end
          request.on(:done) do
            emit_or_callback_error(:request_completed, request)
          end

          request.on(:response_started) do |res|
            if res.is_a?(Response)
              emit_or_callback_error(:response_started, request, res)
              res.on(:chunk_received) do |chunk|
                emit_or_callback_error(:response_body_chunk, request, res, chunk)
              end
            else
              emit_or_callback_error(:request_error, request, res.error)
            end
          end
          request.on(:response) do |res|
            emit_or_callback_error(:response_completed, request, res)
          end
        end

        def emit_or_callback_error(*args)
          emit(*args)
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

        def close(*)
          super
        rescue CallbackError => e
          raise e.cause
        end
      end
    end
    register_plugin :callbacks, Callbacks
  end
end
