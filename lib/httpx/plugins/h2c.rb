# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for upgrading a plaintext HTTP/1.1 connection to HTTP/2
    # (https://tools.ietf.org/html/rfc7540#section-3.2)
    #
    # https://gitlab.com/os85/httpx/wikis/Upgrade#h2c
    #
    module H2C
      VALID_H2C_VERBS = %w[GET OPTIONS HEAD].freeze

      class << self
        def load_dependencies(*)
          require "base64"
        end

        def configure(klass)
          klass.plugin(:upgrade)
          klass.default_options.upgrade_handlers.register "h2c", self
        end

        def call(connection, request, response)
          connection.upgrade_to_h2c(request, response)
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end
      end

      module InstanceMethods
        def send_requests(*requests)
          upgrade_request, *remainder = requests

          return super unless VALID_H2C_VERBS.include?(upgrade_request.verb) && upgrade_request.scheme == "http"

          connection = pool.find_connection(upgrade_request.uri, upgrade_request.options)

          return super if connection && connection.upgrade_protocol == :h2c

          # build upgrade request
          upgrade_request.headers.add("connection", "upgrade")
          upgrade_request.headers.add("connection", "http2-settings")
          upgrade_request.headers["upgrade"] = "h2c"
          upgrade_request.headers["http2-settings"] = HTTP2Next::Client.settings_header(upgrade_request.options.http2_settings)

          super(upgrade_request, *remainder)
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

      module ConnectionMethods
        using URIExtensions

        def upgrade_to_h2c(request, response)
          prev_parser = @parser

          if prev_parser
            prev_parser.reset
            @inflight -= prev_parser.requests.size
          end

          parser_options = @options.merge(max_concurrent_requests: request.options.max_concurrent_requests)
          @parser = H2CParser.new(@write_buffer, parser_options)
          set_parser_callbacks(@parser)
          @inflight += 1
          @parser.upgrade(request, response)
          @upgrade_protocol = :h2c

          if request.options.max_concurrent_requests != @options.max_concurrent_requests
            @options = @options.merge(max_concurrent_requests: nil)
          end

          prev_parser.requests.each do |req|
            req.transition(:idle)
            send(req)
          end
        end
      end
    end
    register_plugin(:h2c, H2C)
  end
end
