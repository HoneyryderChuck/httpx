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
      def self.load_dependencies(*)
        require "httpx/plugins/cookies/jar"
        require "httpx/plugins/cookies/cookie"
        require "httpx/plugins/cookies/set_cookie_parser"
      end

      module OptionsMethods
        def option_cookies(value)
          value.is_a?(Jar) ? value : Jar.new(value)
        end
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

        def on_response(reuest, response)
          if response && response.respond_to?(:headers) && (set_cookie = response.headers["set-cookie"])

            log { "cookies: set-cookie is over #{Cookie::MAX_LENGTH}" } if set_cookie.bytesize > Cookie::MAX_LENGTH

            @options.cookies.parse(set_cookie)
          end

          super
        end

        def build_request(*, _)
          request = super
          request.headers.set_cookie(@options.cookies[request.uri])
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
        def initialize(*)
          super

          return unless @headers.key?("cookie")

          @headers.delete("cookie").each do |ck|
            ck.split(/ *; */).each do |cookie|
              name, value = cookie.split("=", 2)
              @cookies.add(Cookie.new(name, value))
            end
          end
        end
      end
    end
    register_plugin :cookies, Cookies
  end
end
