# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  module Plugins
    module Proxy
      module Socks4
        VERSION = 4
        CONNECT = 1
        GRANTED = 90

        Error = Class.new(Error)

        class Socks4ProxyChannel < ProxyChannel
          private

          def proxy_connect
            @parser = SocksParser.new(@write_buffer, @options)
            @parser.once(:packet, &method(:on_packet))
          end

          def on_packet(packet)
            _version, status, _port, _ip = packet.unpack("CCnN")
            if status == GRANTED
              req, _ = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options) if request_uri.scheme == "https"
              transition(:connected)
              throw(:called)
            else
              response = ErrorResponse.new(Error.new("socks error: #{status}"), 0, @options)
              until @pending.empty?
                req, _ = @pending.shift
                emit(:response, req, response)
              end
            end
          end

          def transition(nextstate)
            case nextstate
            when :connecting
              return unless @state == :idle
              @io.connect
              return unless @io.connected?
              req, _ = @pending.first
              return unless req
              request_uri = req.uri
              @write_buffer << Packet.connect(@parameters, request_uri)
              proxy_connect
            when :connected
              return unless @state == :connecting
              @parser = nil
            end
            log(level: 1, label: "SOCKS4: ") { "#{nextstate}: #{@write_buffer.to_s.inspect}" } unless nextstate == :open
            super
          end
        end
        Parameters.register("socks4", Socks4ProxyChannel)
        Parameters.register("socks4a", Socks4ProxyChannel)

        class SocksParser
          include Callbacks

          def initialize(buffer, options)
            @buffer = buffer
            @options = Options.new(options)
          end

          def close; end

          def consume(*); end

          def empty?
            true
          end

          def <<(packet)
            emit(:packet, packet)
          end
        end

        module Packet
          module_function

          def connect(parameters, uri)
            packet = [VERSION, CONNECT, uri.port].pack("CCn")
            begin
              ip = IPAddr.new(uri.host)
              raise Error, "Socks4 connection to #{ip} not supported" unless ip.ipv4?
              packet << [ip.to_i].pack("N")
            rescue IPAddr::InvalidAddressError
              if parameters.uri.scheme == "socks4"
                # resolv defaults to IPv4, and socks4 doesn't support IPv6 otherwise
                ip = IPAddr.new(Resolv.getaddress(uri.host))
                packet << [ip.to_i].pack("N")
              else
                packet << "\x0\x0\x0\x1" << "\x7\x0" << uri.host
              end
            end
            packet << [parameters.username].pack("Z*")
            packet
          end
        end
      end
    end
    register_plugin :"proxy/socks4", Proxy::Socks4
  end
end
