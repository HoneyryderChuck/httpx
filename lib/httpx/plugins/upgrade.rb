# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin helps negotiating a new protocol from an HTTP/1.1 connection, via the
    # Upgrade header.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Upgrade
    #
    module Upgrade
      class << self
        def configure(klass)
          klass.plugin(:"upgrade/h2")
        end

        def extra_options(options)
          upgrade_handlers = Module.new do
            extend Registry
          end

          Class.new(options.class) do
            def_option(:upgrade_handlers, <<-OUT)
              raise Error, ":upgrade_handlers must be a registry" unless value.respond_to?(:registry)

              value
            OUT
          end.new(options).merge(upgrade_handlers: upgrade_handlers)
        end
      end

      module InstanceMethods
        def fetch_response(request, connections, options)
          response = super

          if response
            return response unless response.respond_to?(:headers) && response.headers.key?("upgrade")

            upgrade_protocol = response.headers["upgrade"].split(/ *, */).first

            return response unless upgrade_protocol && options.upgrade_handlers.registry.key?(upgrade_protocol)

            protocol_handler = options.upgrade_handlers.registry(upgrade_protocol)

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
