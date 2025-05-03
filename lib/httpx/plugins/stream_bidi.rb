# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for bidirectional HTTP/2 streams.
    #
    # https://gitlab.com/os85/httpx/wikis/StreamBidi
    #
    # It is required that the request body allows chunk to be buffered, (i.e., responds to +#<<(chunk)+).
    module StreamBidi
      # Extension of the Connection::HTTP2 class, which adds functionality to
      # deal with a request that can't be drained and must be interleaved with
      # the response streams.
      #
      # The streams keeps send DATA frames while there's data; when they're ain't,
      # the stream is kept open; it must be explicitly closed by the end user.
      #
      class HTTP2Bidi < Connection::HTTP2
        def initialize(*)
          super
          @lock = Thread::Mutex.new
        end

        %i[close empty? exhausted? send <<].each do |lock_meth|
          class_eval(<<-METH, __FILE__, __LINE__ + 1)
            # lock.aware version of +#{lock_meth}+
            def #{lock_meth}(*)                # def close(*)
              return super if @lock.owned?

              # small race condition between
              # checking for ownership and
              # acquiring lock.
              # TODO: fix this at the parser.
              @lock.synchronize { super }
            end
          METH
        end

        private

        %i[join_headers join_trailers join_body].each do |lock_meth|
          class_eval(<<-METH, __FILE__, __LINE__ + 1)
            # lock.aware version of +#{lock_meth}+
            def #{lock_meth}(*)                # def join_headers(*)
              return super if @lock.owned?

              # small race condition between
              # checking for ownership and
              # acquiring lock.
              # TODO: fix this at the parser.
              @lock.synchronize { super }
            end
          METH
        end

        def handle_stream(stream, request)
          request.on(:body) do
            next unless request.headers_sent

            handle(request, stream)

            emit(:flush_buffer)
          end
          super
        end

        # when there ain't more chunks, it makes the buffer as full.
        def send_chunk(request, stream, chunk, next_chunk)
          super

          return if next_chunk

          request.transition(:waiting_for_chunk)
          throw(:buffer_full)
        end

        # sets end-stream flag when the request is closed.
        def end_stream?(request, next_chunk)
          request.closed? && next_chunk.nil?
        end
      end

      # BidiBuffer is a Buffer which can be receive data from threads othr
      # than the thread of the corresponding Connection/Session.
      #
      # It synchronizes access to a secondary internal +@oob_buffer+, which periodically
      # is reconciled to the main internal +@buffer+.
      class BidiBuffer < Buffer
        def initialize(*)
          super
          @parent_thread = Thread.current
          @oob_mutex = Thread::Mutex.new
          @oob_buffer = "".b
        end

        # buffers the +chunk+ to be sent
        def <<(chunk)
          return super if Thread.current == @parent_thread

          @oob_mutex.synchronize { @oob_buffer << chunk }
        end

        # reconciles the main and secondary buffer (which receives data from other threads).
        def rebuffer
          raise Error, "can only rebuffer while waiting on a response" unless Thread.current == @parent_thread

          @oob_mutex.synchronize do
            @buffer << @oob_buffer
            @oob_buffer.clear
          end
        end
      end

      # Proxy to wake up the session main loop when one
      # of the connections has buffered data to write. It abides by the HTTPX::_Selectable API,
      # which allows it to be registered in the selector alongside actual HTTP-based
      # HTTPX::Connection objects.
      class Signal
        def initialize
          @closed = false
          @pipe_read, @pipe_write = ::IO.pipe
        end

        def state
          @closed ? :closed : :open
        end

        # noop
        def log(**); end

        def to_io
          @pipe_read.to_io
        end

        def wakeup
          return if @closed

          @pipe_write.write("\0")
        end

        def call
          return if @closed

          @pipe_read.readpartial(1)
        end

        def interests
          return if @closed

          :r
        end

        def timeout; end

        def terminate
          @pipe_write.close
          @pipe_read.close
          @closed = true
        end

        # noop (the owner connection will take of it)
        def handle_socket_timeout(interval); end
      end

      class << self
        def load_dependencies(klass)
          klass.plugin(:stream)
        end

        def extra_options(options)
          options.merge(fallback_protocol: "h2")
        end
      end

      module InstanceMethods
        def initialize(*)
          @signal = Signal.new
          super
        end

        def close(selector = Selector.new)
          @signal.terminate
          selector.deregister(@signal)
          super(selector)
        end

        def select_connection(connection, selector)
          super
          selector.register(@signal)
          connection.signal = @signal
        end

        def deselect_connection(connection, *)
          super
          connection.signal = nil
        end
      end

      # Adds synchronization to request operations which may buffer payloads from different
      # threads.
      module RequestMethods
        attr_accessor :headers_sent

        def initialize(*)
          super
          @headers_sent = false
          @closed = false
          @mutex = Thread::Mutex.new
        end

        def closed?
          @closed
        end

        def can_buffer?
          super && @state != :waiting_for_chunk
        end

        # overrides state management transitions to introduce an intermediate
        # +:waiting_for_chunk+ state, which the request transitions to once payload
        # is buffered.
        def transition(nextstate)
          headers_sent = @headers_sent

          case nextstate
          when :waiting_for_chunk
            return unless @state == :body
          when :body
            case @state
            when :headers
              headers_sent = true
            when :waiting_for_chunk
              # HACK: to allow super to pass through
              @state = :headers
            end
          end

          super.tap do
            # delay setting this up until after the first transition to :body
            @headers_sent = headers_sent
          end
        end

        def <<(chunk)
          @mutex.synchronize do
            if @drainer
              @body.clear if @body.respond_to?(:clear)
              @drainer = nil
            end
            @body << chunk

            transition(:body)
          end
        end

        def close
          @mutex.synchronize do
            return if @closed

            @closed = true
          end

          # last chunk to send which ends the stream
          self << ""
        end
      end

      module RequestBodyMethods
        def initialize(*, **)
          super
          @headers.delete("content-length")
        end

        def empty?
          false
        end
      end

      # overrides the declaration of +@write_buffer+, which is now a thread-safe buffer
      # responding to the same API.
      module ConnectionMethods
        attr_writer :signal

        def initialize(*)
          super
          @write_buffer = BidiBuffer.new(@options.buffer_size)
        end

        # rebuffers the +@write_buffer+ before calculating interests.
        def interests
          @write_buffer.rebuffer

          super
        end

        private

        def parser_type(protocol)
          return HTTP2Bidi if protocol == "h2"

          super
        end

        def set_parser_callbacks(parser)
          super
          parser.on(:flush_buffer) do
            @signal.wakeup if @signal
          end
        end
      end
    end
    register_plugin :stream_bidi, StreamBidi
  end
end
