# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin helps negotiating a new protocol from an HTTP/1.1 connection, via the
    # Upgrade header.
    #
    # https://gitlab.com/os85/httpx/wikis/Upgrade
    #
    module Upgrade
      class << self
        def configure(klass)
          klass.plugin(:"upgrade/h2")
        end

        def extra_options(options)
          options.merge(upgrade_handlers: {})
        end
      end

      module OptionsMethods
        def option_upgrade_handlers(value)
          raise TypeError, ":upgrade_handlers must be a Hash" unless value.is_a?(Hash)

          value
        end
      end

      module InstanceMethods
        def fetch_response(request, selector, options)
          response = super

          if response
            return response unless response.is_a?(Response)

            return response unless response.headers.key?("upgrade")

            upgrade_protocol = response.headers["upgrade"].split(/ *, */).first

            return response unless upgrade_protocol && options.upgrade_handlers.key?(upgrade_protocol)

            protocol_handler = options.upgrade_handlers[upgrade_protocol]

            return response unless protocol_handler

            log { "upgrading to #{upgrade_protocol}..." }
            connection = find_connection(request.uri, selector, options)

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
      end

      module ConnectionMethods
        attr_reader :upgrade_protocol, :hijacked

        def initialize(*)
          super

          @upgrade_protocol = nil
        end

        def hijack_io
          @hijacked = true

          # connection is taken away from selector and not given back to the pool.
          @current_session.deselect_connection(self, @current_selector, true)
        end
      end
    end
    register_plugin(:upgrade, Upgrade)
  end
end
