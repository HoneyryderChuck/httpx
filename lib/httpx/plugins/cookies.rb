# frozen_string_literal: true

module HTTPX
  module Plugins
    module Cookies
      def self.load_dependencies(*)
        require "http/cookie"
      end

      module InstanceMethods
        def initialize(*)
          @cookies_store = {}
          super
        end

        def cookies(cookies)
          branch(default_options.with_cookies(cookies))
        end

        private

        def on_response(request, response)
          @cookies_store[request.origin] = response.cookies
          super
        end

        def __build_req(*)
          request = super
          request.headers.cookies(@cookies_store[request.origin], request)
          request.headers.cookies(@options.cookies, request)
          request
        end
      end

      module HeadersMethods
        def cookies(jar, request)
          return unless jar

          unless jar.is_a?(HTTP::CookieJar)
            jar = jar.each_with_object(HTTP::CookieJar.new) do |(cookie, v), j|
              unless cookie.is_a?(HTTP::Cookie)
                cookie = HTTP::Cookie.new(cookie.to_s, v.to_s)
                cookie.domain = request.authority
                cookie.path = request.path
              end
              j.add(cookie)
            end
          end
          add("cookie", HTTP::Cookie.cookie_value(jar.cookies(request.uri)))
        end
      end

      module ResponseMethods
        def cookie_jar
          return @cookie_jar if defined?(@cookie_jar)
          return nil unless headers.key?("set-cookie")

          @cookie_jar = begin
            jar = HTTP::CookieJar.new
            jar.parse(headers["set-cookie"], @request.uri)
            jar
          end
        end
        alias_method :cookies, :cookie_jar
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
