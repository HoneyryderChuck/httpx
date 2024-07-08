# frozen_string_literal: true

module HTTPX
  class Socks5Error < HTTPProxyError; end

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

        Error = Socks5Error

        class << self
          def load_dependencies(*)
            require_relative "../auth/socks5"
          end

          def extra_options(options)
            options.merge(supported_proxy_protocols: options.supported_proxy_protocols + %w[socks5])
          end
        end

        module ConnectionMethods
          def call
            super

            return unless @options.proxy && @options.proxy.uri.scheme == "socks5"

            case @state
            when :connecting,
                 :negotiating,
                 :authenticating
              consume
            end
          end

          def connecting?
            super || @state == :authenticating || @state == :negotiating
          end

          def interests
            if @state == :connecting || @state == :authenticating || @state == :negotiating
              return @write_buffer.empty? ? :r : :w
            end

            super
          end

          private

          def handle_transition(nextstate)
            return super unless @options.proxy && @options.proxy.uri.scheme == "socks5"

            case nextstate
            when :connecting
              return unless @state == :idle

              @io.connect
              return unless @io.connected?

              @write_buffer << Packet.negotiate(@options.proxy)
              __socks5_proxy_connect
            when :authenticating
              return unless @state == :connecting

              @write_buffer << Packet.authenticate(@options.proxy)
            when :negotiating
              return unless @state == :connecting || @state == :authenticating

              req = @pending.first
              request_uri = req.uri
              @write_buffer << Packet.connect(request_uri)
            when :connected
              return unless @state == :negotiating

              @parser = nil
            end
            log(level: 1) { "SOCKS5: #{nextstate}: #{@write_buffer.to_s.inspect}" } unless nextstate == :open
            super
          end

          def __socks5_proxy_connect
            @parser = SocksParser.new(@write_buffer, @options)
            @parser.on(:packet, &method(:__socks5_on_packet))
            transition(:negotiating)
          end

          def __socks5_on_packet(packet)
            case @state
            when :connecting
              version, method = packet.unpack("CC")
              __socks5_check_version(version)
              case method
              when PASSWD
                transition(:authenticating)
                nil
              when NONE
                __on_socks5_error("no supported authorization methods")
              else
                transition(:negotiating)
              end
            when :authenticating
              _, status = packet.unpack("CC")
              return transition(:negotiating) if status == SUCCESS

              __on_socks5_error("socks authentication error: #{status}")
            when :negotiating
              version, reply, = packet.unpack("CC")
              __socks5_check_version(version)
              __on_socks5_error("socks5 negotiation error: #{reply}") unless reply == SUCCESS
              req = @pending.first
              request_uri = req.uri
              @io = ProxySSL.new(@io, request_uri, @options) if request_uri.scheme == "https"
              transition(:connected)
              throw(:called)
            end
          end

          def __socks5_check_version(version)
            __on_socks5_error("invalid SOCKS version (#{version})") if version != 5
          end

          def __on_socks5_error(message)
            ex = Error.new(message)
            ex.set_backtrace(caller)
            on_error(ex)
            throw(:called)
          end
        end

        class SocksParser
          include HTTPX::Callbacks

          def initialize(buffer, options)
            @buffer = buffer
            @options = options
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
            methods << PASSWD if parameters.can_authenticate?
            methods.unshift(methods.size)
            methods.unshift(VERSION)
            methods.pack("C*")
          end

          def authenticate(parameters)
            parameters.authenticate
          end

          def connect(uri)
            packet = [VERSION, CONNECT, 0].pack("C*")
            begin
              ip = IPAddr.new(uri.host)

              ipcode = ip.ipv6? ? IPV6 : IPV4

              packet << [ipcode].pack("C") << ip.hton
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
