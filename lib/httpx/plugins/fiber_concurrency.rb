# frozen_string_literal: true

module HTTPX
  module Plugins
    # This plugin makes a session reuse the same selector across all fibers in a given thread.
    #
    # This enables integration with fiber scheduler implementations such as [async](https://github.com/async).
    #
    # # https://gitlab.com/os85/httpx/wikis/Fiber-Concurrency
    #
    module FiberConcurrency
      def self.subplugins
        {
          h2c: FiberConcurrencyH2C,
          stream: FiberConcurrencyStream,
        }
      end

      module InstanceMethods
        private

        def send_request(request, *)
          request.set_context!

          super
        end

        def get_current_selector
          super(&nil) || begin
            return unless block_given?

            default = yield

            set_current_selector(default)

            default
          end
        end
      end

      module RequestMethods
        # the execution context (fiber) this request was sent on.
        attr_reader :context

        def initialize(*)
          super
          @context = nil
        end

        # sets the execution context for this request. the default is the current fiber.
        def set_context!
          @context ||= Fiber.current # rubocop:disable Naming/MemoizedInstanceVariableName
        end

        # checks whether the current execution context is the one where the request was created.
        def current_context?
          @context == Fiber.current
        end

        def complete!(response = @response)
          @context = nil
          super
        end
      end

      module ConnectionMethods
        def current_context?
          @pending.any?(&:current_context?) || (
            @sibling && @sibling.pending.any?(&:current_context?)
          )
        end

        def interests
          return if connecting? && @pending.none?(&:current_context?)

          super
        end

        def on_io_error(e)
          return super unless e.is_a?(IOError) && e.message.include?("stream closed in another thread")

          return unless to_io.closed?

          if @state == :closing
            # IO closed in another fiber, transition to closed
            call
          elsif !backlog?
            super
          end
        end

        def on_connect_error(e)
          # TODO: return super if this is not stream closed in another thread
          return super unless e.is_a?(IOError) && e.message.include?("stream closed in another thread")

          return unless to_io.closed? && !backlog?

          super
        end

        private

        def backlog?
          @pending.any? ||
            (@parser && (@parser.pending.any? || @parser.requests.any?))
        end
      end

      module HTTP1Methods
        def interests
          request = @request || @requests.first

          return unless request

          return unless request.current_context? || @requests.any?(&:current_context?) || @pending.any?(&:current_context?)

          super
        end
      end

      module HTTP2Methods
        def initialize(*)
          super
          @contexts = Hash.new { |hs, k| hs[k] = Set.new }
        end

        def interests
          if @connection.state == :connected && @handshake_completed && !@contexts.key?(Fiber.current)
            return :w unless @pings.empty?

            return
          end

          super
        end

        def send(request, *)
          add_to_context(request)

          super
        end

        private

        def on_close(_, error, _)
          if error == :http_1_1_required
            # remove all pending requests context
            @pending.each do |req|
              clear_from_context(req)
            end
          end

          super
        end

        def on_stream_close(_, request, error)
          clear_from_context(request) if error != :stream_closed && @streams.key?(request)

          super
        end

        def teardown(request = nil)
          super

          if request
            clear_from_context(request)
          else
            @contexts.clear
          end
        end

        def add_to_context(request)
          @contexts[request.context] << request
        end

        def clear_from_context(request)
          requests = @contexts[request.context]

          requests.delete(request)

          @contexts.delete(request.context) if requests.empty?
        end
      end

      module ResolverNativeMethods
        def calculate_interests
          return if @queries.empty?

          return unless @queries.values.any?(&:current_context?) || @connections.any?(&:current_context?)

          super
        end

        def disconnect
          return unless @connections.all?(&:current_context?)

          super
        end

        def on_io_error(e)
          # TODO: return super if this is not stream clsed in another thread

          log { "IO Erroring: #{e.message}, current:#{@name}, queries:#{@queries.size}" }
          return unless @name

          super
        end
      end

      module ResolverSystemMethods
        def interests
          return unless @queries.any? { |_, conn| conn.current_context? }

          super
        end
      end

      module FiberConcurrencyH2C
        module HTTP2Methods
          def upgrade(request, *)
            @contexts[request.context] << request

            super
          end
        end
      end

      module FiberConcurrencyStream
        module StreamResponseMethods
          def close
            unless @request.current_context?
              @request.close

              return
            end

            super
          end
        end
      end
    end

    register_plugin :fiber_concurrency, FiberConcurrency
  end
end
