# frozen_string_literal: true

module HTTPX
  module Plugins
    module Upgrade
      extend Registry

      def self.load_dependencies(klass)
        klass.plugin(:"upgrade/h2")
      end

      module InstanceMethods
        def fetch_response(request, connections, options)
          response = super

          if response && response.headers.key?("upgrade")

            upgrade_protocol = response.headers["upgrade"].split(/ *, */).first

            return response unless upgrade_protocol && Upgrade.registry.key?(upgrade_protocol)

            protocol_handler = Upgrade.registry(upgrade_protocol)

            return response unless protocol_handler

            log { "upgrading to #{upgrade_protocol}..." }
            connection = find_connection(request, connections, options)
            connections << connection unless connections.include?(connection)

            # do not upgrade already upgraded connections
            return if connection.upgrade_protocol == upgrade_protocol

            protocol_handler.call(connection, request, response)

            # keep in the loop if the server is switching, unless
            # the connection has been hijacked, in which case you want
            # to terminante immediately
            return if response.status == 101 && !connection.hijacked
          end

          response
        end

        def close(*args)
          return super if args.empty?

          connections, = args

          pool.close(connections.reject(&:hijacked))
        end
      end

      module ConnectionMethods
        attr_reader :upgrade_protocol, :hijacked

        def hijack_io
          @hijacked = true
        end
      end
    end
    register_plugin(:upgrade, Upgrade)
  end
end
