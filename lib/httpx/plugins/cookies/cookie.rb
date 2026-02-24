# frozen_string_literal: true

module HTTPX
  module Plugins::Cookies
    # The HTTP Cookie.
    #
    # Contains the single cookie info: name, value and attributes.
    class Cookie
      include Comparable

      # Maximum number of bytes per cookie (RFC 6265 6.1 requires 4096 at
      # least)
      MAX_LENGTH = 4096

      attr_reader :domain, :path, :name, :value, :created_at

      # assigns a new +path+ to this cookie.
      def path=(path)
        path = String(path)
        @for_domain = false
        @path = path.start_with?("/") ? path : "/"
      end

      # assigns a new +domain+ to this cookie.
      def domain=(domain)
        domain = String(domain)

        if domain.start_with?(".")
          @for_domain = true
          domain = domain[1..-1]
        end

        return if domain.empty?

        @domain_name = DomainName.new(domain)
        # RFC 6265 5.3 5.
        @for_domain = false if @domain_name.domain.nil? # a public suffix or IP address

        @domain = @domain_name.hostname
      end

      # checks whether +other+ is the same cookie, i.e. name, value, domain and path are
      # the same.
      def ==(other)
        @name == other.name && @value == other.value &&
          @path == other.path && @domain == other.domain
      end

      # Compares the cookie with another.  When there are many cookies with
      # the same name for a URL, the value of the smallest must be used.
      def <=>(other)
        # RFC 6265 5.4
        # Precedence: 1. longer path  2. older creation
        (@name <=> other.name).nonzero? ||
          (other.path.length <=> @path.length).nonzero? ||
          (@created_at <=> other.created_at).nonzero? || 0
      end

      def match?(name_or_options)
        case name_or_options
        when String
          @name == name_or_options
        when Hash, Array
          name_or_options.all? { |k, v| respond_to?(k) && send(k) == v }
        else
          false
        end
      end

      class << self
        def new(cookie, *args)
          case cookie
          when self
            cookie
          when Array, Hash
            options = Hash[cookie] #: cookie_attributes
            super(options[:name], options[:value], options)
          else

            super
          end
        end

        # Tests if +target_path+ is under +base_path+ as described in RFC
        # 6265 5.1.4.  +base_path+ must be an absolute path.
        # +target_path+ may be empty, in which case it is treated as the
        # root path.
        #
        # e.g.
        #
        #         path_match?('/admin/', '/admin/index') == true
        #         path_match?('/admin/', '/Admin/index') == false
        #         path_match?('/admin/', '/admin/') == true
        #         path_match?('/admin/', '/admin') == false
        #
        #         path_match?('/admin', '/admin') == true
        #         path_match?('/admin', '/Admin') == false
        #         path_match?('/admin', '/admins') == false
        #         path_match?('/admin', '/admin/') == true
        #         path_match?('/admin', '/admin/index') == true
        def path_match?(base_path, target_path)
          base_path.start_with?("/") || (return false)
          # RFC 6265 5.1.4
          bsize = base_path.size
          tsize = target_path.size
          return bsize == 1 if tsize.zero? # treat empty target_path as "/"
          return false unless target_path.start_with?(base_path)
          return true if bsize == tsize || base_path.end_with?("/")

          target_path[bsize] == "/"
        end
      end

      def initialize(arg, value, attrs = nil)
        @created_at = Time.now

        @name = arg
        @value = value
        attr_hash = Hash.try_convert(attrs)

        attr_hash.each do |key, val|
          key = key.downcase.tr("-", "_").to_sym unless key.is_a?(Symbol)

          case key
          when :domain, :path
            __send__(:"#{key}=", val)
          else
            instance_variable_set(:"@#{key}", val)
          end
        end if attr_hash

        @path ||= "/"
        raise ArgumentError, "name must be specified" if @name.nil?

        @name = @name.to_s
      end

      def expires
        @expires || (@created_at && @max_age ? @created_at + @max_age : nil)
      end

      def expired?(time = Time.now)
        return false unless expires

        expires <= time
      end

      # Returns a string for use in the Cookie header, i.e. `name=value`
      # or `name="value"`.
      def cookie_value
        "#{@name}=#{Scanner.quote(@value.to_s)}"
      end
      alias_method :to_s, :cookie_value

      # Tests if it is OK to send this cookie to a given `uri`.  A
      # RuntimeError is raised if the cookie's domain is unknown.
      def valid_for_uri?(uri)
        uri = URI(uri)
        # RFC 6265 5.4

        return false if @secure && uri.scheme != "https"

        acceptable_from_uri?(uri) && Cookie.path_match?(@path, uri.path)
      end

      private

      # Tests if it is OK to accept this cookie if it is sent from a given
      # URI/URL, `uri`.
      def acceptable_from_uri?(uri)
        uri = URI(uri)

        host = DomainName.new(uri.host)

        # RFC 6265 5.3
        if host.hostname == @domain
          true
        elsif @for_domain # !host-only-flag
          host.cookie_domain?(@domain_name)
        else
          @domain.nil?
        end
      end

      module Scanner
        RE_BAD_CHAR = /([\x00-\x20\x7F",;\\])/.freeze

        module_function

        def quote(s)
          return s unless s.match(RE_BAD_CHAR)

          "\"#{s.gsub(/([\\"])/, "\\\\\\1")}\""
        end
      end
    end
  end
end
