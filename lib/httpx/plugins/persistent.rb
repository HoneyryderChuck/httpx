# frozen_string_literal: true

module HTTPX
  module Plugins
    # This plugin implements a session that persists connections over the duration of the process.
    #
    # This will improve connection reuse in a long-running process.
    #
    # One important caveat to note is, although this session might not close connections,
    # other sessions from the same process that don't have this plugin turned on might.
    #
    # This session will still be able to work with it, as if, when expecting a connection
    # terminated by a different session, it will just retry on a new one and keep it open.
    #
    # This plugin is also not recommendable when connecting to >9000 (like, a lot) different origins.
    # So when you use this, make sure that you don't fall into this trap.
    #
    # https://gitlab.com/os85/httpx/wikis/Persistent
    #
    module Persistent
      def self.load_dependencies(klass)
        max_retries = if klass.default_options.respond_to?(:max_retries)
          [klass.default_options.max_retries, 1].max
        else
          1
        end
        klass.plugin(:retries, max_retries: max_retries, retry_change_requests: true)
      end

      def self.extra_options(options)
        options.merge(persistent: true)
      end

      module InstanceMethods
        private

        def get_current_selector
          super(&nil) || begin
            return unless block_given?

            default = yield

            set_current_selector(default)

            default
          end
        end
      end
    end
    register_plugin :persistent, Persistent
  end
end
