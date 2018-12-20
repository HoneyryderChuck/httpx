# frozen_string_literal: true

require "httpx/plugins/proxy"

module HTTPX
  module Plugins
    module Proxy
      module SSH
      	def self.load_dependencies(klass, *)
          # klass.plugin(:proxy)
          require "net/ssh/gateway"
      	end

        module InstanceMethods
          def with_proxy(*args)
            branch(default_options.with_proxy(*args))
          end

          private

          def __send_reqs(*requests, **options)
            ssh_options = @options.proxy
            ssh_uris = ssh_options.delete(:uri)
            ssh_username = ssh_options.delete(:username)
            ssh_uri = URI.parse(ssh_uris.shift)
            ssh_options[:port] ||= ssh_uri.port || 22 
            if @options.debug
              ssh_options[:verbose] = @options.debug_level == 2 ? :debug : :info
            end
            request_uri = URI(requests.first.uri)
            @_gateway = Net::SSH::Gateway.new(ssh_uri.host, ssh_username, ssh_options)
            begin
              @_gateway.open(request_uri.host, request_uri.port) do |local_port|
                io = TCPSocket.open("localhost", local_port)
                super(*requests, **options.merge(io: io))
              end
            ensure
              @_gateway.shutdown!
            end
          end
        end

        module OptionsMethods
          def self.included(klass)
            super
            klass.def_option(:proxy) do |pr|
              Hash[pr]
            end
          end
        end
      end
    end
    register_plugin :"proxy/ssh", Proxy::SSH
  end
end