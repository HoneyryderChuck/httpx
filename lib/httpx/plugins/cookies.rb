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
          @headers.cookies(@options.cookies, self)
        end
      end

      module HeadersMethods
        def cookies(jar, request)
          return unless jar
          unless jar.is_a?(HTTP::CookieJar)
            jar = jar.each_with_object(HTTP::CookieJar.new) do |(k, v), j|
              cookie = k.is_a?(HTTP::Cookie) ? v : HTTP::Cookie.new(k.to_s, v.to_s)
              cookie.domain = request.authority
              cookie.path = request.path
              j.add(cookie)
            end
          end
          self["cookie"] = HTTP::Cookie.cookie_value(jar.cookies)
        end
      end

      module ResponseMethods
        def cookie_jar
          return @cookies if defined?(@cookies)
          return nil unless headers.key?("set-cookie")
          @cookies ||= begin
            jar = HTTP::CookieJar.new
            jar.parse(headers["set-cookie"], @request.uri)
            jar
          end
        end
        alias :cookies :cookie_jar
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
