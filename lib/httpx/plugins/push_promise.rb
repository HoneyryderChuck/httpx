# frozen_string_literal: true

module HTTPX
  module Plugins
    module PushPromise
      PUSH_OPTIONS = { http2_settings: { settings_enable_push: 1 } }

      module InstanceMethods
        def initialize(opts = {})
          super(PUSH_OPTIONS.merge(opts))
        end
      end
    end
    register_plugin(:push_promise, PushPromise)
  end
end 
