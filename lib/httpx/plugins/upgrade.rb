# frozen_string_literal: true

module HTTPX
  module Plugins
    module Upgrade
      extend Registry

      module InstanceMethods
        def fetch_response(request, connections, options)
          response = super

          if response && response.status == 101
            connection = find_connection(request, connections, options)
            connections << connection unless connections.include?(connection)

            upgrade_protocol = (request.headers.get("upgrade") & response.headers.get("upgrade")).first

            protocol_handler = Upgrade.registry(upgrade_protocol)

            return response unless protocol_handler

            log { "upgrading to #{upgrade_protocol}..." }

            # TODO: exit it connection already upgraded?
            protocol_handler.call(connection, request, response)

            return
          end
          response
        end
      end

      module ConnectionMethods
        attr_reader :upgrade_protocol
      end
    end
    register_plugin(:upgrade, Upgrade)
  end
end
