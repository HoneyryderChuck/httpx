# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  module Plugins
    module Proxy
      module Socks4 
        GRANTED = 90
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
            if status == GRANTED
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
        Parameters.register("socks4a", Socks4ProxyChannel)
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
        VERSION = 4
        CONNECT = 1
        attr_accessor :response

        def initialize(parameters, request_uri)
          @parameters = parameters
          @uri = request_uri
          @host = @uri.host
          @socks_version = @parameters.uri.scheme
          @done = false
        end

        def done?
          @done
        end

        def done!
          @done = true
        end

        def to_packet
          packet = [VERSION, CONNECT, @uri.port].pack("CCn")
          begin
            ip = IPAddr.new(@host)
            raise Error, "Socks4 connection to #{ip.to_s} not supported" unless ip.ipv4?
            packet << [ip.to_i].pack("N")
          rescue IPAddr::InvalidAddressError
            if @socks_version == "socks4"
              # resolv defaults to IPv4, and socks4 doesn't support IPv6 otherwise
              ip = IPAddr.new(Resolv.getaddress(@host))
              packet << [ip.to_i].pack("N")
            else
              packet << "\x0\x0\x0\x1" << "\x7\x0" << @host
            end
          end
          packet << [@parameters.username].pack("Z*")
          packet
        end
      end
    end
    register_plugin :"proxy/socks4", Proxy::Socks4
  end
end

