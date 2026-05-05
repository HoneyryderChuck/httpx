# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for upgrading an HTTP/1.1 connection to HTTP/2
    # via an Upgrade: h2 response declaration
    #
    # https://gitlab.com/os85/httpx/wikis/Connection-Upgrade#h2
    #
    module H2
      class << self
        def extra_options(options)
          options.merge(upgrade_handlers: options.upgrade_handlers.merge("h2" => self))
        end

        def call(connection, _request, _response)
          connection.upgrade_to_h2
        end
      end

      module ConnectionMethods
        using URIExtensions

        def interests
          return super unless connecting? && @parser

          connect

          return @io.interests if connecting?

          super
        end

        def upgrade_to_h2
          enqueue_pending_requests_from_parser(@parser)

          @parser = @options.http2_class.new(@write_buffer, @options)
          set_parser_callbacks(@parser)
          @upgrade_protocol = "h2"

          # what's happening here:
          # a deviation from the state machine is done to perform the actions when a
          # connection is closed, without transitioning, so the connection is kept in the pool.
          # the state is reset to initial, so that the socket reconnect works out of the box,
          # while the parser is already here.
          purge_after_closed
          transition(:idle)
        end
      end
    end
    register_plugin(:"upgrade/h2", H2)
  end
end
