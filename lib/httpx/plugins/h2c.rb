# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for upgrading a plaintext HTTP/1.1 connection to HTTP/2
    # (https://tools.ietf.org/html/rfc7540#section-3.2)
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Follow-Redirects
    #
    module H2C
      def self.load_dependencies(*)
        require "base64"
      end

      module InstanceMethods
        def request(*args, **options)
          h2c_options = options.merge(fallback_protocol: "h2c")

          requests = build_requests(*args, h2c_options)

          upgrade_request = requests.first
          return super unless valid_h2c_upgrade_request?(upgrade_request)

          upgrade_request.headers.add("connection", "upgrade")
          upgrade_request.headers.add("connection", "http2-settings")
          upgrade_request.headers["upgrade"] = "h2c"
          upgrade_request.headers["http2-settings"] = HTTP2Next::Client.settings_header(upgrade_request.options.http2_settings)
          wrap { send_requests(*upgrade_request, h2c_options).first }

          responses = send_requests(*requests, h2c_options)

          responses.size == 1 ? responses.first : responses
        end

        private

        def fetch_response(request, connections, options)
          response = super
          if response && valid_h2c_upgrade?(request, response, options)
            log { "upgrading to h2c..." }
            connection = find_connection(request, connections, options)
            connections << connection unless connections.include?(connection)
            connection.upgrade(request, response)
          end
          response
        end

        VALID_H2C_METHODS = %i[get options head].freeze
        private_constant :VALID_H2C_METHODS

        def valid_h2c_upgrade_request?(request)
          VALID_H2C_METHODS.include?(request.verb) &&
            request.scheme == "http"
        end

        def valid_h2c_upgrade?(request, response, options)
          options.fallback_protocol == "h2c" &&
            request.headers.get("connection").include?("upgrade") &&
            request.headers.get("upgrade").include?("h2c") &&
            response.status == 101
        end
      end

      class H2CParser < Connection::HTTP2
        def upgrade(request, response)
          @connection.send_connection_preface
          # skip checks, it is assumed that this is the first
          # request in the connection
          stream = @connection.upgrade
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

        def match?(uri, options)
          return super unless uri.scheme == "http" && @options.fallback_protocol == "h2c"

          super && options.fallback_protocol == "h2c"
        end

        def coalescable?(connection)
          return super unless @options.fallback_protocol == "h2c" && @origin.scheme == "http"

          @origin == connection.origin && connection.options.fallback_protocol == "h2c"
        end

        def upgrade(request, response)
          @parser.reset if @parser
          @parser = H2CParser.new(@write_buffer, @options)
          set_parser_callbacks(@parser)
          @parser.upgrade(request, response)
        end

        def build_parser(*)
          return super unless @origin.scheme == "http"

          super("http/1.1")
        end
      end
    end
    register_plugin(:h2c, H2C)
  end
end
