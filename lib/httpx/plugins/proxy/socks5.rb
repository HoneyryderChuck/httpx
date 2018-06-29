# frozen_string_literal: true

module HTTPX
  module Plugins
    module Proxy
      module Socks5
        VERSION = 5
        NOAUTH = 0
        PASSWD = 2
        NONE   = 0xff
        CONNECT = 1
        IPV4 = 1
        DOMAIN = 3
        IPV6 = 4
        SUCCESS = 0

        Error = Class.new(Error)

        class Socks5ProxyChannel < ProxyChannel
          def call
            super
            case @state
            when :connecting,
                 :negotiating,
                 :authenticating
              consume
            end
          end

          private

          def proxy_connect
            @parser = SocksParser.new(@write_buffer, @options)
            @parser.on(:packet, &method(:on_packet))
            transition(:negotiating)
          end

          def on_packet(packet)
            case @state
            when :connecting
              version, method = packet.unpack("CC")
              check_version(version)
              case method
              when PASSWD
                transition(:authenticating)
                return
              when NONE
                on_socks_error("no supported authorization methods")
              else
                transition(:negotiating)
              end
            when :authenticating
              version, status = packet.unpack("CC")
              check_version(version)
              return transition(:negotiating) if status == SUCCESS
              on_socks_error("socks authentication error: #{status}")
            when :negotiating
              version, reply, = packet.unpack("CC")
              check_version(version)
              on_socks_error("socks5 negotiation error: #{reply}") unless reply == SUCCESS
              req, _ = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options) if request_uri.scheme == "https"
              transition(:connected)
              throw(:called)
            end
          end

          def transition(nextstate)
            case nextstate
            when :connecting
              return unless @state == :idle
              @io.connect
              return unless @io.connected?
              @write_buffer << Packet.negotiate(@parameters)
              proxy_connect
            when :authenticating
              return unless @state == :connecting
              @write_buffer << Packet.authenticate(@parameters)
            when :negotiating
              return unless @state == :connecting || @state == :authenticating
              req, _ = @pending.first
              request_uri = req.uri
              @write_buffer << Packet.connect(request_uri)
            when :connected
              return unless @state == :negotiating
              @parser = nil
            end
            log(level: 1, label: "SOCKS5: ") { "#{nextstate}: #{@write_buffer.to_s.inspect}" } unless nextstate == :open
            super
          end

          def check_version(version)
            on_socks_error("invalid SOCKS version (#{version})") if version != 5
          end

          def on_socks_error(message)
            ex = Error.new(message)
            ex.set_backtrace(caller)
            on_error(ex)
            throw(:called)
          end
        end

        Parameters.register("socks5", Socks5ProxyChannel)

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

          def negotiate(parameters)
            methods = [NOAUTH]
            methods << PASSWD if parameters.authenticated?
            methods.unshift(methods.size)
            methods.unshift(VERSION)
            methods.pack("C*")
          end

          def authenticate(parameters)
            user = parameters.username
            pass = parameters.password
            [0x01, user.bytesize, user, pass.bytesize, password].pack("CCA*CA*")
          end

          def connect(uri)
            packet = [VERSION, CONNECT, 0].pack("C*")
            begin
              ip = IPAddr.new(uri.host)
              raise Error, "Socks4 connection to #{ip} not supported" unless ip.ipv4?
              packet << [IPV4, ip.to_i].pack("CN")
            rescue IPAddr::InvalidAddressError
              packet << [DOMAIN, uri.host.bytesize, uri.host].pack("CCA*")
            end
            packet << [uri.port].pack("n")
            packet
          end
        end
      end
    end
    register_plugin :"proxy/socks5", Proxy::Socks5
  end
end
