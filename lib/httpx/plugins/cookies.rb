# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    #
    # This plugin implements a persistent cookie jar for the duration of a session.
    #
    # It also adds a *#cookies* helper, so that you can pre-fill the cookies of a session.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Cookies
    #
    module Cookies
      using URIExtensions

      def self.extra_options(options)
        Class.new(options.class) do
          def_option(:cookies) do |cookies|
            if cookies.is_a?(Store)
              cookies
            else
              Store.new(cookies)
            end
          end
        end.new(options)
      end

      class Store
        def self.new(cookies = nil)
          return cookies if cookies.is_a?(self)

          super
        end

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

        def ==(other)
          @store == other.instance_variable_get(:@store)
        end
      end

      def self.load_dependencies(*)
        require "http/cookie"
      end

      module InstanceMethods
        extend Forwardable

        def_delegator :@options, :cookies

        def initialize(options = {}, &blk)
          super({ cookies: Store.new }.merge(options), &blk)
        end

        def with_cookies(cookies)
          branch(default_options.with_cookies(cookies))
        end

        def wrap
          return super unless block_given?

          super do |session|
            old_cookies_store = @options.cookies.dup
            begin
              yield session
            ensure
              @options = @options.with_cookies(old_cookies_store)
            end
          end
        end

        private

        def on_response(request, response)
          @options.cookies.set(request.origin, response.headers["set-cookie"]) if response.respond_to?(:headers)

          super
        end

        def build_request(*, _)
          request = super
          request.headers.set_cookie(@options.cookies[request.uri])
          request
        end
      end

      module HeadersMethods
        def set_cookie(jar)
          return unless jar

          cookie_value = HTTP::Cookie.cookie_value(jar.cookies)
          return if cookie_value.empty?

          add("cookie", cookie_value)
        end
      end
    end
    register_plugin :cookies, Cookies
  end
end
