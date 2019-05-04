# frozen_string_literal: true

module HTTPX
  module Plugins
    module H2C
      def self.load_dependencies(*)
        require "base64"
      end

      module InstanceMethods
        def request(*args, **options)
          h2c_options = options.merge(fallback_protocol: "h2c")

          requests = __build_reqs(*args, h2c_options)

          upgrade_request = requests.first
          return super unless valid_h2c_upgrade_request?(upgrade_request)

          upgrade_request.headers["upgrade"] = "h2c"
          upgrade_request.headers.add("connection", "upgrade")
          upgrade_request.headers.add("connection", "http2-settings")
          upgrade_request.headers["http2-settings"] = HTTP2::Client.settings_header(upgrade_request.options.http2_settings)
          upgrade_response = wrap { __send_reqs(*upgrade_request, h2c_options).first }

          if upgrade_response.status == 101
            # if 101, assume that connection exists and was kept open
            connection = find_connection(upgrade_request, upgrade_request.options)
            connection.upgrade(upgrade_request, upgrade_response)

            response = upgrade_request.response
            if response.status == 200
              requests.delete(upgrade_request)
              return response if requests.empty?
            end
            responses = __send_reqs(*requests, h2c_options)
          else
            # proceed as usual
            responses = [upgrade_response] + __send_reqs(*requests[1..-1], h2c_options)
          end

          return responses.first if responses.size == 1

          responses
        end

        private

        VALID_H2C_METHODS = %i[get options head].freeze
        private_constant :VALID_H2C_METHODS

        def valid_h2c_upgrade_request?(request)
          VALID_H2C_METHODS.include?(request.verb) &&
            request.scheme == "http"
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
          data = response.to_s
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
          return super unless @options.fallback_protocol == "h2c" && @uri.scheme == "http"

          @uri.origin == connection.uri.origin && connection.options.fallback_protocol == "h2c"
        end

        def upgrade(request, response)
          @parser.reset if @parser
          @parser = H2CParser.new(@write_buffer, @options)
          set_parser_callbacks(@parser)
          @parser.upgrade(request, response)
        end

        def build_parser(*)
          return super unless @uri.scheme == "http"

          super("http/1.1")
        end
      end

      module FrameBuilder
        include HTTP2

        module_function

        def settings_value(settings)
          frame = Framer.new.generate(type: :settings, stream: 0, payload: settings)
          Base64.urlsafe_encode64(frame[9..-1])
        end
      end
    end
    register_plugin(:h2c, H2C)
  end
end
