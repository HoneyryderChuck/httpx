# frozen_string_literal: true

module HTTPX
  module Plugins::Cookies
    # The Cookie Jar
    #
    # It stores and manages cookies for a session, such as i.e. evicting when expired, access methods, or
    # initialization from parsing `Set-Cookie` HTTP header values.
    #
    # It closely follows the [CookieStore API](https://developer.mozilla.org/en-US/docs/Web/API/CookieStore),
    # by implementing the same methods, with a few specific conveniences for this non-browser manipulation use-case.
    #
    class Jar
      using URIExtensions

      include Enumerable

      def initialize_dup(orig)
        super
        @cookies = orig.instance_variable_get(:@cookies).dup
      end

      # initializes the cookie store, either empty, or with whatever is passed as +cookies+, which
      # can be an array of HTTPX::Plugins::Cookies::Cookie objects or hashes-or-tuples of cookie attributes.
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

      # parses the `Set-Cookie` header value as +set_cookie+ and does the corresponding updates.
      def parse(set_cookie)
        SetCookieParser.call(set_cookie) do |name, value, attrs|
          set(Cookie.new(name, value, attrs))
        end
      end

      # returns the first HTTPX::Plugins::Cookie::Cookie instance in the store which matches either the name
      # (when String) or all attributes (when a Hash or array of tuples) passed to +name_or_options+
      def get(name_or_options)
        each.find { |ck| ck.match?(name_or_options) }
      end

      # returns all HTTPX::Plugins::Cookie::Cookie instances in the store which match either the name
      # (when String) or all attributes (when a Hash or array of tuples) passed to +name_or_options+
      def get_all(name_or_options)
        each.select { |ck| ck.match?(name_or_options) } # rubocop:disable Style/SelectByRegexp
      end

      # when +name+ is a HTTPX::Plugins::Cookie::Cookie, it stores it internally; when +name+ is a String,
      # it creates a cookie with it and the value-or-attributes passed to +value_or_options+.

      # optionally, +name+ can also be the attributes hash-or-array as long it contains a <tt>:name</tt> field).
      def set(name, value_or_options = nil)
        cookie = case name
                 when Cookie
                   raise ArgumentError, "there should not be a second argument" if value_or_options

                   name
                 when Array, Hash
                   raise ArgumentError, "there should not be a second argument" if value_or_options

                   Cookie.new(name)
                 else
                   raise ArgumentError, "the second argument is required" unless value_or_options

                   Cookie.new(name, value_or_options)
        end

        # If the user agent receives a new cookie with the same cookie-name, domain-value, and path-value
        # as a cookie that it has already stored, the existing cookie is evicted and replaced with the new cookie.
        @cookies.delete_if { |ck| ck.name == cookie.name && ck.domain == cookie.domain && ck.path == cookie.path }

        @cookies << cookie
      end

      # @deprecated
      def add(cookie, path = nil)
        warn "DEPRECATION WARNING: calling `##{__method__}` is deprecated. Use `#set` instead."
        c = cookie.dup
        c.path = path if path && c.path == "/"
        set(c)
      end

      # deletes all cookies  in the store which match either the name (when String) or all attributes (when a Hash
      # or array of tuples) passed to +name_or_options+.
      #
      # alternatively, of +name_or_options+ is an instance of HTTPX::Plugins::Cookies::Cookiem, it deletes it from the store.
      def delete(name_or_options)
        case name_or_options
        when Cookie
          @cookies.delete(name_or_options)
        else
          @cookies.delete_if { |ck| ck.match?(name_or_options) }
        end
      end

      # returns the list of valid cookies which matdh the domain and path from the URI object passed to +uri+.
      def [](uri)
        each(uri).sort
      end

      # enumerates over all stored cookies. if +uri+ is passed, it'll filter out expired cookies and
      # only yield cookies which match its domain and path.
      def each(uri = nil, &blk)
        return enum_for(__method__, uri) unless blk

        return @cookies.each(&blk) unless uri

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

      def merge(other)
        jar_dup = dup

        other.each do |elem|
          cookie = case elem
                   when Cookie
                     elem
                   when Array
                     Cookie.new(*elem)
                   else
                     Cookie.new(elem)
          end

          jar_dup.set(cookie)
        end

        jar_dup
      end
    end
  end
end
