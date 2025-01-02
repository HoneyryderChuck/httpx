# frozen_string_literal: true

require "httpx/version"

# Top-Level Namespace
#
module HTTPX
  EMPTY = [].freeze
  EMPTY_HASH = {}.freeze

  # All plugins should be stored under this module/namespace. Can register and load
  # plugins.
  #
  module Plugins
    @plugins = {}
    @plugins_mutex = Thread::Mutex.new

    # Loads a plugin based on a name. If the plugin hasn't been loaded, tries to load
    # it from the load path under "httpx/plugins/" directory.
    #
    def self.load_plugin(name)
      h = @plugins
      m = @plugins_mutex
      unless (plugin = m.synchronize { h[name] })
        require "httpx/plugins/#{name}"
        raise "Plugin #{name} hasn't been registered" unless (plugin = m.synchronize { h[name] })
      end
      plugin
    end

    # Registers a plugin (+mod+) in the central store indexed by +name+.
    #
    def self.register_plugin(name, mod)
      h = @plugins
      m = @plugins_mutex
      m.synchronize { h[name] = mod }
    end
  end
end

require "httpx/extensions"

require "httpx/errors"
require "httpx/utils"
require "httpx/punycode"
require "httpx/domain_name"
require "httpx/altsvc"
require "httpx/callbacks"
require "httpx/loggable"
require "httpx/transcoder"
require "httpx/timers"
require "httpx/pool"
require "httpx/headers"
require "httpx/request"
require "httpx/response"
require "httpx/options"
require "httpx/chainable"

require "httpx/session"
require "httpx/session_extensions"

# load integrations when possible

require "httpx/adapters/datadog" if defined?(DDTrace) || defined?(Datadog::Tracing)
require "httpx/adapters/sentry" if defined?(Sentry)
require "httpx/adapters/webmock" if defined?(WebMock)
