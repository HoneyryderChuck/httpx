# frozen_string_literal: true

module HTTPX
  module Plugins
    module H2C
      def self.load_dependencies(*)
        require "base64"
      end

      module InstanceMethods
        def request(*args, **options)
          return super if @_h2c_probed

          begin
            requests = __build_reqs(*args, options)

            upgrade_request = requests.first
            return super unless valid_h2c_upgrade_request?(upgrade_request)

            upgrade_request.headers["upgrade"] = "h2c"
            upgrade_request.headers.add("connection", "upgrade")
            upgrade_request.headers.add("connection", "http2-settings")
            upgrade_request.headers["http2-settings"] = HTTP2::Client.settings_header(upgrade_request.http2_settings)
            upgrade_response = wrap { __send_reqs(*upgrade_request, options).first }

            if upgrade_response.status == 101
              # if 101, assume that connection exists and was kept open
              connection = find_connection(upgrade_request, options)
              parser = connection.upgrade_parser("h2")
              parser.extend(UpgradeExtensions)
              parser.upgrade(upgrade_request, upgrade_response, **upgrade_request.options)

              # clean up data left behind in the buffer, if the server started
              # sending frames
              data = upgrade_response.to_s
              parser << data

              response = upgrade_request.response
              if response.status == 200
                requests.delete(upgrade_request)
                return response if requests.empty?
              end
              responses = __send_reqs(*requests, options)
            else
              # proceed as usual
              responses = [upgrade_response] + __send_reqs(*requests[1..-1], options)
            end

            return responses.first if responses.size == 1

            responses
          ensure
            @_h2c_probed = true
          end
        end

        private

        VALID_H2C_METHODS = %i[get options head].freeze
        private_constant :VALID_H2C_METHODS

        def valid_h2c_upgrade_request?(request)
          VALID_H2C_METHODS.include?(request.verb) &&
            request.scheme == "http"
        end
      end

      module RequestMethods
        def self.included(klass)
          klass.__send__(:attr_reader, :options)
          klass.def_delegator :@options, :http2_settings
        end
      end

      module UpgradeExtensions
        def upgrade(request, _response, **)
          @connection.send_connection_preface
          # skip checks, it is assumed that this is the first
          # request in the connection
          stream = @connection.upgrade
          handle_stream(stream, request)
          @streams[request] = stream
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
