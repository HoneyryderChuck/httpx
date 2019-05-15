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
    module Persistent
      def self.load_dependencies(klass, *)
        klass.plugin(:retries) # TODO: pass default max_retries -> 1 as soon as this is a parameter
      end

      def self.extra_options(options)
        options.merge(persistent: true)
      end
    end
    register_plugin :persistent, Persistent
  end
end
