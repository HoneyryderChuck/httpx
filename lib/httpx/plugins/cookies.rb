# frozen_string_literal: true

module HTTPX
  module Plugins
    module Cookies
      using URIExtensions

      def self.extra_options(options)
        Class.new(options.class) do
          def_option(:cookies) do |cookies|
            return cookies if cookies.is_a?(Store)

            Store.new(cookies)
          end
        end.new(options)
      end

      class Store
        def initialize(cookies = nil)
          @store = Hash.new { |hash, origin| hash[origin] = HTTP::CookieJar.new }
          return unless cookies

          cookies = cookies.split(/ *; */) if cookies.is_a?(String)
          @default_cookies = cookies.map do |cookie, v|
            if cookie.is_a?(HTTP::Cookie)
              cookie
            else
              HTTP::Cookie.new(cookie.to_s, v.to_s)
            end
          end
        end

        def set(origin, cookies)
          return unless cookies

          @store[origin].parse(cookies, origin)
        end

        def [](uri)
          store = @store[uri.origin]
          @default_cookies.each do |cookie|
            c = cookie.dup
            c.domain ||= uri.authority
            c.path ||= uri.path
            store.add(c)
          end if @default_cookies
          store
        end
      end

      def self.load_dependencies(*)
        require "http/cookie"
      end

      module InstanceMethods
        attr_reader :cookies_store

        def initialize(*)
          super
          @cookies_store = @options.cookies || Store.new
        end

        def with_cookies(cookies)
          branch(default_options.with_cookies(cookies))
        end

        def wrap
          return unless block_given?

          super do |session|
            old_cookies_store = @cookies_store
            @cookies_store = old_cookies_store.dup
            begin
              yield session
            ensure
              @cookies_store = old_cookies_store
            end
          end
        end

        private

        def on_response(request, response)
          @cookies_store.set(request.origin, response.headers["set-cookie"])
          super
        end

        def __build_req(*, _)
          request = super
          request.headers.cookies(@cookies_store[request.uri], request)
          request
        end
      end

      module HeadersMethods
        def cookies(jar, request)
          return unless jar

          cookie_value = HTTP::Cookie.cookie_value(jar.cookies(request.uri))
          return if cookie_value.empty?

          add("cookie", cookie_value)
        end
      end
    end
    register_plugin :cookies, Cookies
  end
end
