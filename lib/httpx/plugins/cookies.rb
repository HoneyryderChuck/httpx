# frozen_string_literal: true

module HTTPX
  module Plugins
    module Cookies
      def self.load_dependencies(*)
        require "http/cookie"
      end

      module InstanceMethods
        def cookies(cookies)
          branch(default_options.with_cookies(cookies))
        end
      end

      module RequestMethods
        def initialize(*)
          super
          @headers.cookies(@options.cookies)
        end
      end

      module HeadersMethods
        def cookies(cookies)
          cookies.each do |k, v|
            cookie = k.is_a?(HTTP::Cookie) ? k : HTTP::Cookie.new(k.to_s, v.to_s)
            add("cookie", cookie.cookie_value)
          end
        end
      end

      module ResponseMethods
        def cookies
          headers["cookie"]
        end
      end

      module OptionsMethods
        def self.included(klass)
          super
          klass.def_option(:cookies) do |cookies|
            cookies.split(/ *; */) if cookies.is_a?(String)
            cookies
          end
        end
      end 
    end
    register_plugin :cookies, Cookies 
  end
end
