# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  Socks4Error = Class.new(Error)
  module Plugins
    module Proxy
      module Socks4
        VERSION = 4
        CONNECT = 1
        GRANTED = 90
        PROTOCOLS = %w[socks4 socks4a].freeze

        Error = Socks4Error

        module ConnectionMethods
          private

          def transition(nextstate)
            return super unless @options.proxy && PROTOCOLS.include?(@options.proxy.uri.scheme)

            case nextstate
            when :connecting
              return unless @state == :idle

              @io.connect
              return unless @io.connected?

              req = @pending.first
              return unless req

              request_uri = req.uri
              @write_buffer << Packet.connect(@options.proxy, request_uri)
              __socks4_proxy_connect
            when :connected
              return unless @state == :connecting

              @parser = nil
            end
            log(level: 1) { "SOCKS4: #{nextstate}: #{@write_buffer.to_s.inspect}" } unless nextstate == :open
            super
          end

          def __socks4_proxy_connect
            @parser = SocksParser.new(@write_buffer, @options)
            @parser.once(:packet, &method(:__socks4_on_packet))
          end

          def __socks4_on_packet(packet)
            _version, status, _port, _ip = packet.unpack("CCnN")
            if status == GRANTED
              req = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options) if request_uri.scheme == "https"
              transition(:connected)
              throw(:called)
            else
              on_socks4_error("socks error: #{status}")
            end
          end

          def on_socks4_error(message)
            ex = Error.new(message)
            ex.set_backtrace(caller)
            on_error(ex)
            throw(:called)
          end
        end

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
              if parameters.uri.scheme =~ /^socks4a?$/
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
