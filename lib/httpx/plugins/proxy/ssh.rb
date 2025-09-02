# frozen_string_literal: true

require "httpx/plugins/proxy"

module HTTPX
  module Plugins
    module Proxy
      module SSH
        class << self
          def load_dependencies(*)
            require "net/ssh/gateway"
          end
        end

        module OptionsMethods
          private

          def option_proxy(value)
            Hash[value]
          end
        end

        module InstanceMethods
          def request(*args, **options)
            raise ArgumentError, "must perform at least one request" if args.empty?

            requests = args.first.is_a?(Request) ? args : build_requests(*args, options)

            request = requests.first or return super

            request_options = request.options

            return super unless request_options.proxy

            ssh_options = request_options.proxy
            ssh_uris = ssh_options.delete(:uri)
            ssh_uri = URI.parse(ssh_uris.shift)

            return super unless ssh_uri.scheme == "ssh"

            ssh_username = ssh_options.delete(:username)
            ssh_options[:port] ||= ssh_uri.port || 22
            if request_options.debug
              ssh_options[:verbose] = request_options.debug_level == 2 ? :debug : :info
            end

            request_uri = URI(requests.first.uri)
            @_gateway = Net::SSH::Gateway.new(ssh_uri.host, ssh_username, ssh_options)
            begin
              @_gateway.open(request_uri.host, request_uri.port) do |local_port|
                io = build_gateway_socket(local_port, request_uri, request_options)
                super(*args, **options.merge(io: io))
              end
            ensure
              @_gateway.shutdown!
            end
          end

          private

          def build_gateway_socket(port, request_uri, options)
            case request_uri.scheme
            when "https"
              ctx = OpenSSL::SSL::SSLContext.new
              ctx_options = SSL::TLS_OPTIONS.merge(options.ssl)
              ctx.set_params(ctx_options) unless ctx_options.empty?
              sock = TCPSocket.open("localhost", port)
              io = OpenSSL::SSL::SSLSocket.new(sock, ctx)
              io.hostname = request_uri.host
              io.sync_close = true
              io.connect
              io.post_connection_check(request_uri.host) if ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE
              io
            when "http"
              TCPSocket.open("localhost", port)
            else
              raise TypeError, "unexpected scheme: #{request_uri.scheme}"
            end
          end
        end

        module ConnectionMethods
          # should not coalesce connections here, as the IP is the IP of the proxy
          def coalescable?(*)
            return super unless @options.proxy

            false
          end
        end
      end
    end
    register_plugin :"proxy/ssh", Proxy::SSH
  end
end
