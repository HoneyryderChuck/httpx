# frozen_string_literal: true

module HTTPX
  module Plugins::Cookies
    # The Cookie Jar
    #
    # It holds a bunch of cookies.
    class Jar
      using URIExtensions

      include Enumerable

      def initialize_dup(orig)
        super
        @cookies = orig.instance_variable_get(:@cookies).dup
      end

      def initialize(cookies = nil)
        @cookies = []

        cookies.each do |elem|
          cookie = case elem
                   when Cookie
                     elem
                   when Array
                     Cookie.new(*elem)
                   else
                     Cookie.new(elem)
          end

          @cookies << cookie
        end if cookies
      end

      def parse(set_cookie)
        SetCookieParser.call(set_cookie) do |name, value, attrs|
          add(Cookie.new(name, value, attrs))
        end
      end

      def add(cookie, path = nil)
        c = cookie.dup

        c.path = path if path && c.path == "/"

        # If the user agent receives a new cookie with the same cookie-name, domain-value, and path-value
        # as a cookie that it has already stored, the existing cookie is evicted and replaced with the new cookie.
        @cookies.delete_if { |ck| ck.name == c.name && ck.domain == c.domain && ck.path == c.path }

        @cookies << c
      end

      def [](uri)
        each(uri).sort
      end

      def each(uri = nil, &blk)
        return enum_for(__method__, uri) unless block_given?

        return @store.each(&blk) unless uri

        uri = URI(uri)

        now = Time.now
        tpath = uri.path

        @cookies.delete_if do |cookie|
          if cookie.expired?(now)
            true
          else
            yield cookie if cookie.valid_for_uri?(uri) && Cookie.path_match?(cookie.path, tpath)
            false
          end
        end
      end
    end
  end
end
