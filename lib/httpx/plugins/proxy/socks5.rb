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

          private

          def proxy_connect 
            @parser = SocksParser.new(@write_buffer, @options)
            @parser.on(:packet, &method(:on_packet))
            transition(:negotiating)
          end
          
          def on_packet(packet)
            case @state
            when :negotiating
              version, method = packet.unpack("CC")
              check_version(version)
              case method
              when PASSWD
                transition(:authenticating)
                return
              when NONE
                raise Error, "no supported authorization methods"
              else
                transition(:connecting)
              end
            when :authenticating
              version, status = packet.unpack("CC")
              check_version(version)
              raise Error, "could not authorize" if status != SUCCESS
              transition(:connecting)
            when :connecting
              version, reply, = packet.unpack("CC")
              check_version(version)
              raise Error, "Illegal response type" unless reply == SUCCESS
              transition(:open)
              req, _ = @pending.first
              request_uri = req.uri
              if request_uri.scheme == "https"
                @io = ProxySSL.new(@io, request_uri, @options)
              end
              throw(:called)
            end
          end

          def transition(nextstate)
            case nextstate
            when :idle
            when :negotiating
              return unless @state == :idle
              @write_buffer << Packet.negotiate(@parameters)
            when :authenticating
              return unless @state == :negotiating
              @write_buffer << Packet.authenticate(@parameters)
            when :connecting
              return unless @state == :negotiating || @state == :authenticating
              req, _ = @pending.first
              request_uri = req.uri
              @write_buffer << Packet.connect(request_uri)
            when :open
              return unless :connecting
              @parser = nil
            end
            log { "#{nextstate.to_s}: #{@write_buffer.to_s.inspect}" }
            @state = nextstate
          end

          def check_version(version)
            raise Error, "invalid SOCKS version (#{version})" if version != 5
          end
        end
        Parameters.register("socks5", Socks5ProxyChannel)

        class SocksParser
          include Callbacks

          def initialize(buffer, options)
            @buffer = buffer
            @options = Options.new(options)
          end

          def consume(*)
          end

          def <<(packet)
            emit(:packet, packet)
          end

          def log(level=@options.debug_level, &msg)
            return unless @options.debug
            return unless @options.debug_level >= level 
            @options.debug << (+"" << msg.call << "\n")
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
              raise Error, "Socks4 connection to #{ip.to_s} not supported" unless ip.ipv4?
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


