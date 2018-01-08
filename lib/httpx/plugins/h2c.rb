# frozen_string_literal: true

module HTTPX
  module Plugins
    module H2C
      def self.load_dependencies(*)
        require "base64"
      end

      module InstanceMethods
        def request(*args, keep_open: @keep_open, **options)
          return super if @_h2c_probed
          begin
            requests = __build_reqs(*args, **options)

            upgrade_request = requests.first
            return super unless valid_h2c_upgrade_request?(upgrade_request)
            upgrade_request.headers["upgrade"] = "h2c"
            upgrade_request.headers["http2-settings"] = FrameBuilder.settings_value(@default_options.http2_settings)
            # TODO: validate!
            upgrade_response = __send_reqs(*upgrade_request).first
           
            if upgrade_response.status == 101
              channel = find_channel(upgrade_request)
              parser = channel.upgrade_parser("h2")
              parser.extend(UpgradeExtensions)
              parser.upgrade(upgrade_request, upgrade_response, **options)
              data = upgrade_response.to_s
              parser << data 
              responses = __send_reqs(*requests)
            else
              # proceed as usual
              responses = [upgrade_response] + __send_reqs(*requests[1..-1])
            end
            return responses.first if responses.size == 1
            responses 
          ensure
            @_h2c_probed = true 
            close unless keep_open
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

      module UpgradeExtensions
        def upgrade(request, response, retries: @retries, **)
          @connection.send_connection_preface
          # skip checks, it is assumed that this is the first
          # request in the connection
          stream = @connection.new_stream
          # Stream 1 is implicitly "half-closed" from the client toward the server (see Section 5.1)
          stream.__send__(:event, :half_closed_local)
          stream.on(:close) do |error|
            if request.expects?
              return handle(request, stream)
            end
            response = request.response || ErrorResponse.new(error, retries)
            emit(:response, request, response)
            log(2, "#{stream.id}: ") { "closing stream" }


            @streams.delete(request)
            send(@pending.shift) unless @pending.empty?
          end
          stream.on(:half_close) do
            log(2, "#{stream.id}: ") { "waiting for response..." }
          end
          # stream.on(:altsvc)
          stream.on(:headers) do |h|
            log(stream.id) do
              h.map { |k, v| "<- HEADER: #{k}: #{v}" }.join("\n")
            end
            _, status = h.shift
            headers = @options.headers_class.new(h)
            response = @options.response_class.new(request, status, "2.0", headers, @options)
            request.response = response
            @streams[request] = stream 
          end
          stream.on(:data) do |data|
            log(1, "#{stream.id}: ") { "<- DATA: #{data.bytesize} bytes..." }
            log(2, "#{stream.id}: ") { "<- #{data.inspect}" }
            request.response << data
          end
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
