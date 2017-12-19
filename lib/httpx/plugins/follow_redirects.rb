# frozen_string_literal: true

module HTTPX
  module Plugins
    module FollowRedirects
      module InstanceMethods
      end

      module OptionsMethods
        def self.included(klass)
          super
          klass.def_option(:max_redirects)
        end
      end        
    end
    register_plugin :follow_redirects, FollowRedirects
  end
end

