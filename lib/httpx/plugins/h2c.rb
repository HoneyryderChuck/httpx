# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for upgrading a plaintext HTTP/1.1 connection to HTTP/2
    # (https://datatracker.ietf.org/doc/html/rfc7540#section-3.2)
    #
    # https://gitlab.com/os85/httpx/wikis/Connection-Upgrade#h2c
    #
    module H2C
      VALID_H2C_VERBS = %w[GET OPTIONS HEAD].freeze

      class << self
        def load_dependencies(klass)
          klass.plugin(:upgrade)
        end

        def call(connection, request, response)
          connection.upgrade_to_h2c(request, response)
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1, upgrade_handlers: options.upgrade_handlers.merge("h2c" => self))
        end
      end

      class H2CParser < Connection::HTTP2
        def upgrade(request, response)
          # skip checks, it is assumed that this is the first
          # request in the connection
          stream = @connection.upgrade

          # on_settings
          handle_stream(stream, request)
          @streams[request] = stream

          # clean up data left behind in the buffer, if the server started
          # sending frames
          data = response.read
          @connection << data
        end
      end

      module RequestMethods
        def valid_h2c_verb?
          VALID_H2C_VERBS.include?(@verb)
        end
      end

      module ConnectionMethods
        using URIExtensions

        def initialize(*)
          super
          @h2c_handshake = false
        end

        def send(request)
          return super if @h2c_handshake

          return super unless request.valid_h2c_verb? && request.scheme == "http"

          return super if @upgrade_protocol == "h2c"

          @h2c_handshake = true

          # build upgrade request
          request.headers.add("connection", "upgrade")
          request.headers.add("connection", "http2-settings")
          request.headers["upgrade"] = "h2c"
          request.headers["http2-settings"] = ::HTTP2::Client.settings_header(request.options.http2_settings)

          super
        end

        def upgrade_to_h2c(request, response)
          prev_parser = @parser

          if prev_parser
            prev_parser.reset
            @inflight -= prev_parser.requests.size
          end

          @parser = H2CParser.new(@write_buffer, @options)
          set_parser_callbacks(@parser)
          @inflight += 1
          @parser.upgrade(request, response)
          @upgrade_protocol = "h2c"

          prev_parser.requests.each do |req|
            req.transition(:idle)
            send(req)
          end
        end

        private

        def send_request_to_parser(request)
          super

          return unless request.headers["upgrade"] == "h2c" && parser.is_a?(Connection::HTTP1)

          max_concurrent_requests = parser.max_concurrent_requests

          return if max_concurrent_requests == 1

          parser.max_concurrent_requests = 1
          request.once(:response) do
            parser.max_concurrent_requests = max_concurrent_requests
          end
        end
      end
    end
    register_plugin(:h2c, H2C)
  end
end
