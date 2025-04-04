# frozen_string_literal: true

module HTTPX
  module Plugins
    # Extension of the Connection::HTTP2 class, which adds functionality to
    # deal with a request that can't be drained and must be interleaved with
    # the response streams.
    #
    # The streams keeps send DATA frames while there's data; when they're ain't,
    # the stream is kept open; it must be explicitly closed by the end user.
    #
    class HTTP2Bidi < Connection::HTTP2
      private

      def handle_stream(stream, request)
        request.on(:body) do
          next unless request.headers_sent

          handle(request, stream)
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

      def end_stream?(request, *)
        request.closed?
      end
    end

    #
    # This plugin adds support for bidirectional HTTP/2 streams.
    #
    # https://gitlab.com/os85/httpx/wikis/StreamBidi
    #
    module StreamBidi
      class << self
        def load_dependencies(klass)
          klass.plugin(:stream)
        end

        def extra_options(options)
          options.merge(fallback_protocol: "h2")
        end
      end

      module RequestMethods
        attr_accessor :headers_sent

        def initialize(*)
          super
          @headers_sent = false
          @closed = false
        end

        def closed?
          @closed
        end

        def can_buffer?
          super && @state != :waiting_for_chunk
        end

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
          if @drainer
            @body.clear if @body.respond_to?(:clear)
            @drainer = nil
          end
          @body << chunk

          transition(:body)
        end

        def close
          @closed = true

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

      module ConnectionMethods
        def parser_type(protocol)
          return HTTP2Bidi if protocol == "h2"

          super
        end
      end
    end
    register_plugin :stream_bidi, StreamBidi
  end
end
