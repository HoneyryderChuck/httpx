# frozen_string_literal: true

require "ipaddr"

module HTTPX
  module Plugins
    module Proxy
      module Socks 
        class Socks4ProxyChannel < ProxyChannel
          def initialize(*args)
            super(*args)
            @state = :idle
          end

          def send_pending
            return if @pending.empty?
            case @state
            when :open
              # normal flow after connection
              return super
            when :connecting
              return
            when :idle
              transition(:connecting)
              @parser = SocksParser.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
              @parser.once(:response, &method(:on_connect))
              @parser.on(:close) { throw(:close, self) }
              req, _ = @pending.first
              request_uri = req.uri
              connect_request = ConnectRequest.new(@parameters, request_uri)
              parser.send(connect_request)
            end
          end

          private
          
          def on_connect(packet)
            version, status, port, ip = packet.unpack("CCnN")
            if status == 90
              transition(:open)
              req, _ = @pending.first
              request_uri = req.uri
              if request_uri.scheme == "https"
                @io = ProxySSL.new(@io, request_uri, @options)
              end
              throw(:called)
            else
              pending = @parser.instance_variable_get(:@pending)
              while req = pending.shift
                @on_response.call(req, response)
              end
            end
          end

          def transition(nextstate)
            case nextstate
            when :idle
            when :connecting
              return unless @state == :idle
            when :open
              return unless :connecting
              @parser.close
              @parser = nil
            end
            @state = nextstate
          end
        end
        Parameters.register("socks4", Socks4ProxyChannel)
      end

      class SocksParser < Channel::HTTP1

        def close
        end

        def handle(request)
          return if request.done? 
          packet = request.to_packet
          log(2) { "SOCKS: #{packet.inspect}" }
          @buffer << packet
          request.done! 
        end

        def <<(packet)
          emit(:response, packet)
        end
      end

      class ConnectRequest
        attr_accessor :response

        def initialize(parameters, request_uri)
          @parameters = parameters
          @uri = request_uri
          @ip = IPAddr.new(TCPSocket.getaddress(@uri.host))
          @done = false
        end

        def done?
          @done
        end

        def done!
          @done = true
        end

        def to_packet
          [4, 1, @uri.port, @ip.to_i, @parameters.username].pack("CCnNZ*")
        end
      end
    end
  end
end

