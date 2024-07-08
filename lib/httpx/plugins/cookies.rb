# frozen_string_literal: true

require "forwardable"

module HTTPX
  module Plugins
    #
    # This plugin implements a persistent cookie jar for the duration of a session.
    #
    # It also adds a *#cookies* helper, so that you can pre-fill the cookies of a session.
    #
    # https://gitlab.com/os85/httpx/wikis/Cookies
    #
    module Cookies
      def self.load_dependencies(*)
        require "httpx/plugins/cookies/jar"
        require "httpx/plugins/cookies/cookie"
        require "httpx/plugins/cookies/set_cookie_parser"
      end

      module InstanceMethods
        extend Forwardable

        def_delegator :@options, :cookies

        def initialize(options = {}, &blk)
          super({ cookies: Jar.new }.merge(options), &blk)
        end

        def wrap
          return super unless block_given?

          super do |session|
            old_cookies_jar = @options.cookies.dup
            begin
              yield session
            ensure
              @options = @options.merge(cookies: old_cookies_jar)
            end
          end
        end

        private

        def on_response(_request, response)
          if response && response.respond_to?(:headers) && (set_cookie = response.headers["set-cookie"])

            log { "cookies: set-cookie is over #{Cookie::MAX_LENGTH}" } if set_cookie.bytesize > Cookie::MAX_LENGTH

            @options.cookies.parse(set_cookie)
          end

          super
        end

        def build_request(*)
          request = super
          request.headers.set_cookie(request.options.cookies[request.uri])
          request
        end
      end

      module HeadersMethods
        def set_cookie(cookies)
          return if cookies.empty?

          header_value = cookies.sort.join("; ")

          add("cookie", header_value)
        end
      end

      module OptionsMethods
        def option_headers(*)
          value = super

          merge_cookie_in_jar(value.delete("cookie"), @cookies) if defined?(@cookies) && value.key?("cookie")

          value
        end

        def option_cookies(value)
          jar = value.is_a?(Jar) ? value : Jar.new(value)

          merge_cookie_in_jar(@headers.delete("cookie"), jar) if defined?(@headers) && @headers.key?("cookie")

          jar
        end

        private

        def merge_cookie_in_jar(cookies, jar)
          cookies.each do |ck|
            ck.split(/ *; */).each do |cookie|
              name, value = cookie.split("=", 2)
              jar.add(Cookie.new(name, value))
            end
          end
        end
      end
    end
    register_plugin :cookies, Cookies
  end
end
