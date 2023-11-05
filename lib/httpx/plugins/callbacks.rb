# frozen_string_literal: true

module HTTPX
  module Plugins
    module Callbacks
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
            end                    # end
          MOD
        end

        private

        def init_connection(type, uri, options)
          connection = super
          connection.on(:open) do
            emit(:connection_opened, connection.origin, connection.io.socket)
          end
          connection.on(:close) do
            emit(:connection_closed, connection.origin) if connection.used?
          end

          connection
        end

        def set_request_callbacks(request)
          super

          request.on(:headers) do
            emit(:request_started, request)
          end
          request.on(:body_chunk) do |chunk|
            emit(:request_body_chunk, request, chunk)
          end
          request.on(:done) do
            emit(:request_completed, request)
          end

          request.on(:response_started) do |res|
            if res.is_a?(Response)
              emit(:response_started, request, res)
              res.on(:chunk_received) do |chunk|
                emit(:response_body_chunk, request, res, chunk)
              end
            else
              emit(:request_error, request, res.error)
            end
          end
          request.on(:response) do |res|
            emit(:response_completed, request, res)
          end
        end
      end
    end
    register_plugin :callbacks, Callbacks
  end
end
