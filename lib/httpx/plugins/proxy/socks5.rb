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
            @parser = SocksParser.new(@write_buffer, @options.merge(max_concurrent_requests: 1))
            @parser.on(:response, &method(:on_connect))
            @parser.on(:close) { throw(:close, self) }
            transition(:negotiating)
          end
          
          def on_connect(packet)
            case @state
            when :negotiating
              version, method = packet.unpack("CC")
              if version != 5
                raise Error, "invalid SOCKS version (#{version})" 
              end
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
              if version != 5
                raise Error, "invalid SOCKS version (#{version})" 
              end
              if status != SUCCESS
                raise Error, "could not authorize"
              end
              transition(:connecting)
            when :connecting
              version, reply, = packet.unpack("CC")
              raise Error, "Illegal response type" unless reply == SUCCESS
              transition(:open)
            end
          end

          def transition(nextstate)
            case nextstate
            when :idle
            when :negotiating
              return unless @state == :idle
              negotiate_request = NegotiateRequest.new(@parameters)
              parser.send(negotiate_request)
            when :authenticating
              return unless @state == :negotiating
              password_request = PasswordRequest.new(@parameters)
              parser.send(password_request)
            when :connecting
              return unless @state == :negotiating || @state == :authenticating
              req, _ = @pending.first
              request_uri = req.uri
              connect_request = ConnectRequest.new(@parameters, request_uri)
              parser.send(connect_request)
            when :open
              return unless :connecting
              @parser.close
              @parser = nil
            end
            log { nextstate.to_s }
            @state = nextstate
          end
        end
        Parameters.register("socks5", Socks5ProxyChannel)

        class SocksParser < Channel::HTTP1

          def close
          end

          def send(request)
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

        class NegotiateRequest
          attr_accessor :response

          def initialize(parameters)
            @parameters = parameters
            @done = false
          end

          def done?
            @done
          end

          def done!
            @done = true
          end

          def to_packet
            methods = [NOAUTH]
            methods << PASSWD if @parameters.authenticated?
            methods.unshift(methods.size)
            methods.unshift(VERSION)
            methods.pack("C*")
          end
        end

        class PasswordRequest
          def initialize(parameters)
            @parameters = parameters
            @done = false
          end

          def done?
            @done
          end

          def done!
            @done = true
          end

          def to_packet
            user = @parameters.username
            pass = @parameters.password
            [0x01, user.bytesize, user, pass.bytesize, password].pack("CCA*CA*")
          end
        end

        class ConnectRequest
          def initialize(parameters, request_uri)
            @parameters = parameters
            @uri = request_uri
            @host = @uri.host
            @done = false
          end

          def done?
            @done
          end

          def done!
            @done = true
          end

          def to_packet
            packet = [VERSION, CONNECT, 0].pack("C*")
            begin
              ip = IPAddr.new(@host)
              raise Error, "Socks4 connection to #{ip.to_s} not supported" unless ip.ipv4?
              packet << [IPV4, ip.to_i].pack("CN")
            rescue IPAddr::InvalidAddressError
              packet << [DOMAIN, @host.bytesize, @host].pack("CCA*")
            end
            packet << [@uri.port].pack("n")

          end
        end
      end
    end
    register_plugin :"proxy/socks5", Proxy::Socks5
  end
end


