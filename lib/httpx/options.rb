# frozen_string_literal: true

module HTTPX
  # Contains a set of options which are passed and shared across from session to its requests or
  # responses.
  class Options
    BUFFER_SIZE = 1 << 14
    WINDOW_SIZE = 1 << 14 # 16K
    MAX_BODY_THRESHOLD_SIZE = (1 << 10) * 112 # 112K
    KEEP_ALIVE_TIMEOUT = 20
    SETTINGS_TIMEOUT = 10
    CLOSE_HANDSHAKE_TIMEOUT = 10
    CONNECT_TIMEOUT = READ_TIMEOUT = WRITE_TIMEOUT = 60
    REQUEST_TIMEOUT = OPERATION_TIMEOUT = nil
    RESOLVER_TYPES = %i[memory file].freeze

    # default value used for "user-agent" header, when not overridden.
    USER_AGENT = "httpx.rb/#{VERSION}".freeze # rubocop:disable Style/RedundantFreeze

    @options_names = []

    class << self
      attr_reader :options_names

      def inherited(klass)
        super
        klass.instance_variable_set(:@options_names, @options_names.dup)
      end

      def new(options = {})
        # let enhanced options go through
        return options if self == Options && options.class < self
        return options if options.is_a?(self)

        super
      end

      def freeze
        @options_names.freeze
        super
      end

      def method_added(meth)
        super

        return unless meth =~ /^option_(.+)$/

        optname = Regexp.last_match(1) #: String

        if optname =~ /^(.+[^_])_+with/
          # ignore alias method chain generated methods.
          # this is the case with RBS runtime tests.
          # it relies on the "_with/_without" separator, which is the most used convention,
          # however it shouldn't be used in practice in httpx given the plugin architecture
          # as the main extension API.
          orig_name = Regexp.last_match(1) #: String

          return if @options_names.include?(orig_name.to_sym)
        end

        optname = optname.to_sym

        attr_reader(optname) unless method_defined?(optname)

        @options_names << optname unless @options_names.include?(optname)
      end
    end

    # creates a new options instance from a given hash, which optionally define the following:
    #
    # :debug :: an object which log messages are written to (must respond to <tt><<</tt>)
    # :debug_level :: the log level of messages (can be 1, 2, or 3).
    # :debug_redact :: whether header/body payload should be redacted (defaults to <tt>false</tt>).
    # :ssl :: a hash of options which can be set as params of OpenSSL::SSL::SSLContext (see HTTPX::SSL)
    # :http2_settings :: a hash of options to be passed to a HTTP2::Connection (ex: <tt>{ max_concurrent_streams: 2 }</tt>)
    # :fallback_protocol :: version of HTTP protocol to use by default in the absence of protocol negotiation
    #                       like ALPN (defaults to <tt>"http/1.1"</tt>)
    # :supported_compression_formats :: list of compressions supported by the transcoder layer (defaults to <tt>%w[gzip deflate]</tt>).
    # :decompress_response_body :: whether to auto-decompress response body (defaults to <tt>true</tt>).
    # :compress_request_body :: whether to auto-decompress response body (defaults to <tt>true</tt>)
    # :timeout :: hash of timeout configurations (supports <tt>:connect_timeout</tt>, <tt>:settings_timeout</tt>,
    #             <tt>:operation_timeout</tt>, <tt>:keep_alive_timeout</tt>,  <tt>:read_timeout</tt>,  <tt>:write_timeout</tt>
    #             and <tt>:request_timeout</tt>
    # :headers :: hash of HTTP headers (ex: <tt>{ "x-custom-foo" => "bar" }</tt>)
    # :window_size :: number of bytes to read from a socket
    # :buffer_size :: internal read and write buffer size in bytes
    # :body_threshold_size :: maximum size in bytes of response payload that is buffered in memory.
    # :request_class :: class used to instantiate a request
    # :response_class :: class used to instantiate a response
    # :headers_class :: class used to instantiate headers
    # :request_body_class :: class used to instantiate a request body
    # :response_body_class :: class used to instantiate a response body
    # :connection_class :: class used to instantiate connections
    # :http1_class :: class used to manage HTTP1 sessions
    # :http2_class :: class used to imanage HTTP2 sessions
    # :resolver_native_class :: class used to resolve names using pure ruby DNS implementation
    # :resolver_system_class :: class used to resolve names using system-based (getaddrinfo) name resolution
    # :resolver_https_class :: class used to resolve names using DoH
    # :pool_class :: class used to instantiate the session connection pool
    # :options_class :: class used to instantiate options
    # :transport :: type of transport to use (set to "unix" for UNIX sockets)
    # :addresses :: bucket of peer addresses (can be a list of IP addresses, a hash of domain to list of adddresses;
    #               paths should be used for UNIX sockets instead)
    # :io :: open socket, or domain/ip-to-socket hash, which requests should be sent to
    # :persistent :: whether to persist connections in between requests (defaults to <tt>true</tt>)
    # :resolver_class :: which resolver to use (defaults to <tt>:native</tt>, can also be <tt>:system<tt> for
    #                    using getaddrinfo or <tt>:https</tt> for DoH resolver, or a custom class inheriting
    #                    from HTTPX::Resolver::Resolver)
    # :resolver_cache :: strategy to cache DNS results, ignored by the <tt>:system</tt> resolver, can be set to <tt>:memory<tt>
    #                    or an instance of a custom class inheriting from HTTPX::Resolver::Cache::Base
    # :resolver_options :: hash of options passed to the resolver. Accepted keys depend on the resolver type.
    # :pool_options :: hash of options passed to the connection pool (See Pool#initialize).
    # :ip_families :: which socket families are supported (system-dependent)
    # :origin :: HTTP origin to set on requests with relative path (ex: "https://api.serv.com")
    # :base_path :: path to prefix given relative paths with (ex: "/v2")
    # :max_concurrent_requests :: max number of requests which can be set concurrently
    # :max_requests :: max number of requests which can be made on socket before it reconnects.
    # :close_on_fork :: whether the session automatically closes when the process is fork (defaults to <tt>false</tt>).
    #                   it only works if the session is persistent (and ruby 3.1 or higher is used).
    #
    # This list of options are enhanced with each loaded plugin, see the plugin docs for details.
    def initialize(options = EMPTY_HASH)
      options_names = self.class.options_names

      defaults =
        case options
        when Options
          unknown_options = options.class.options_names - options_names

          raise Error, "unknown option: #{unknown_options.first}" unless unknown_options.empty?

          DEFAULT_OPTIONS.merge(options)
        else
          options.each_key do |k|
            raise Error, "unknown option: #{k}" unless options_names.include?(k)
          end

          options.empty? ? DEFAULT_OPTIONS : DEFAULT_OPTIONS.merge(options)
        end

      options_names.each do |k|
        v = defaults[k]

        if v.nil?
          instance_variable_set(:"@#{k}", v)

          next
        end

        value = __send__(:"option_#{k}", v)
        instance_variable_set(:"@#{k}", value)
      end

      do_initialize
      freeze
    end

    # returns the class with which to instantiate the DNS resolver.
    def resolver_class
      case @resolver_class
      when Symbol
        public_send(:"resolver_#{@resolver_class}_class")
      else
        @resolver_class
      end
    end

    def resolver_cache
      cache_type = @resolver_cache

      case cache_type
      when :memory
        Resolver::Cache::Memory.cache(cache_type)
      when :file
        Resolver::Cache::File.cache(cache_type)
      else
        unless cache_type.respond_to?(:resolve) &&
               cache_type.respond_to?(:get) &&
               cache_type.respond_to?(:set) &&
               cache_type.respond_to?(:evict)
          raise TypeError, ":resolver_cache must be a compatible resolver cache and implement #get, #set and #evict"
        end

        cache_type #: Object & Resolver::_Cache
      end
    end

    def freeze
      self.class.options_names.each do |ivar|
        # avoid freezing debug option, as when it's set, it's usually an
        # object which cannot be frozen, like stderr or stdout. It's a
        # documented exception then, and still does not defeat the purpose
        # here, which is to make option objects shareable across ractors,
        # and in most cases debug should be nil, or one of the objects
        # which will eventually be shareable, like STDOUT or STDERR.
        next if ivar == :debug

        instance_variable_get(:"@#{ivar}").freeze
      end
      super
    end

    REQUEST_BODY_IVARS = %i[@headers].freeze

    def ==(other)
      super || options_equals?(other)
    end

    # checks whether +other+ is equal by comparing the session options
    def options_equals?(other, ignore_ivars = REQUEST_BODY_IVARS)
      # headers and other request options do not play a role, as they are
      # relevant only for the request.
      ivars = instance_variables - ignore_ivars
      other_ivars = other.instance_variables - ignore_ivars

      return false if ivars.size != other_ivars.size

      return false if ivars.sort != other_ivars.sort

      ivars.all? do |ivar|
        instance_variable_get(ivar) == other.instance_variable_get(ivar)
      end
    end

    # returns a HTTPX::Options instance resulting of the merging of +other+ with self.
    # it may return self if +other+ is self or equal to self.
    def merge(other)
      if (is_options = other.is_a?(Options))

        return self if eql?(other)

        opts_names = other.class.options_names

        return self if opts_names.all? { |opt| public_send(opt) == other.public_send(opt) }

        other_opts = opts_names
      else
        other_opts = other # : Hash[Symbol, untyped]
        other_opts = Hash[other] unless other.is_a?(Hash)

        return self if other_opts.empty?

        return self if other_opts.all? { |opt, v| !respond_to?(opt) || public_send(opt) == v }
      end

      opts = dup

      other_opts.each do |opt, v|
        next unless respond_to?(opt)

        v = other.public_send(opt) if is_options
        ivar = :"@#{opt}"

        unless v
          opts.instance_variable_set(ivar, v)
          next
        end

        v = opts.__send__(:"option_#{opt}", v)

        orig_v = public_send(opt)

        v = orig_v.merge(v) if orig_v.respond_to?(:merge) && v.respond_to?(:merge)

        opts.instance_variable_set(ivar, v)
      end

      opts
    end

    def to_hash
      instance_variables.each_with_object({}) do |ivar, hs|
        val = instance_variable_get(ivar)

        next if val.nil?

        hs[ivar[1..-1].to_sym] = val
      end
    end

    def extend_with_plugin_classes(pl)
      # extend request class
      if defined?(pl::RequestMethods) || defined?(pl::RequestClassMethods)
        @request_class = @request_class.dup
        SET_TEMPORARY_NAME[@request_class, pl]
        @request_class.__send__(:include, pl::RequestMethods) if defined?(pl::RequestMethods)
        @request_class.extend(pl::RequestClassMethods) if defined?(pl::RequestClassMethods)
      end
      # extend response class
      if defined?(pl::ResponseMethods) || defined?(pl::ResponseClassMethods)
        @response_class = @response_class.dup
        SET_TEMPORARY_NAME[@response_class, pl]
        @response_class.__send__(:include, pl::ResponseMethods) if defined?(pl::ResponseMethods)
        @response_class.extend(pl::ResponseClassMethods) if defined?(pl::ResponseClassMethods)
      end
      # extend headers class
      if defined?(pl::HeadersMethods) || defined?(pl::HeadersClassMethods)
        @headers_class = @headers_class.dup
        SET_TEMPORARY_NAME[@headers_class, pl]
        @headers_class.__send__(:include, pl::HeadersMethods) if defined?(pl::HeadersMethods)
        @headers_class.extend(pl::HeadersClassMethods) if defined?(pl::HeadersClassMethods)
      end
      # extend request body class
      if defined?(pl::RequestBodyMethods) || defined?(pl::RequestBodyClassMethods)
        @request_body_class = @request_body_class.dup
        SET_TEMPORARY_NAME[@request_body_class, pl]
        @request_body_class.__send__(:include, pl::RequestBodyMethods) if defined?(pl::RequestBodyMethods)
        @request_body_class.extend(pl::RequestBodyClassMethods) if defined?(pl::RequestBodyClassMethods)
      end
      # extend response body class
      if defined?(pl::ResponseBodyMethods) || defined?(pl::ResponseBodyClassMethods)
        @response_body_class = @response_body_class.dup
        SET_TEMPORARY_NAME[@response_body_class, pl]
        @response_body_class.__send__(:include, pl::ResponseBodyMethods) if defined?(pl::ResponseBodyMethods)
        @response_body_class.extend(pl::ResponseBodyClassMethods) if defined?(pl::ResponseBodyClassMethods)
      end
      # extend connection pool class
      if defined?(pl::PoolMethods)
        @pool_class = @pool_class.dup
        SET_TEMPORARY_NAME[@pool_class, pl]
        @pool_class.__send__(:include, pl::PoolMethods)
      end
      # extend connection class
      if defined?(pl::ConnectionMethods)
        @connection_class = @connection_class.dup
        SET_TEMPORARY_NAME[@connection_class, pl]
        @connection_class.__send__(:include, pl::ConnectionMethods)
      end
      # extend http1 class
      if defined?(pl::HTTP1Methods)
        @http1_class = @http1_class.dup
        SET_TEMPORARY_NAME[@http1_class, pl]
        @http1_class.__send__(:include, pl::HTTP1Methods)
      end
      # extend http2 class
      if defined?(pl::HTTP2Methods)
        @http2_class = @http2_class.dup
        SET_TEMPORARY_NAME[@http2_class, pl]
        @http2_class.__send__(:include, pl::HTTP2Methods)
      end
      # extend native resolver class
      if defined?(pl::ResolverNativeMethods)
        @resolver_native_class = @resolver_native_class.dup
        SET_TEMPORARY_NAME[@resolver_native_class, pl]
        @resolver_native_class.__send__(:include, pl::ResolverNativeMethods)
      end
      # extend system resolver class
      if defined?(pl::ResolverSystemMethods)
        @resolver_system_class = @resolver_system_class.dup
        SET_TEMPORARY_NAME[@resolver_system_class, pl]
        @resolver_system_class.__send__(:include, pl::ResolverSystemMethods)
      end
      # extend https resolver class
      if defined?(pl::ResolverHTTPSMethods)
        @resolver_https_class = @resolver_https_class.dup
        SET_TEMPORARY_NAME[@resolver_https_class, pl]
        @resolver_https_class.__send__(:include, pl::ResolverHTTPSMethods)
      end

      return unless defined?(pl::OptionsMethods)

      # extend option class
      # works around lack of initialize_dup callback
      @options_class = @options_class.dup
      # (self.class.options_names)
      @options_class.__send__(:include, pl::OptionsMethods)
    end

    private

    # number options
    %i[
      max_concurrent_requests max_requests window_size buffer_size
      body_threshold_size debug_level
    ].each do |option|
      class_eval(<<-OUT, __FILE__, __LINE__ + 1)
        # converts +v+ into an Integer before setting the +#{option}+ option.
        private def option_#{option}(value)                                             # private def option_max_requests(v)
          value = Integer(value) unless value.respond_to?(:infinite?) && value.infinite?
          raise TypeError, ":#{option} must be positive" unless value.positive? # raise TypeError, ":max_requests must be positive" unless value.positive?

          value
        end
      OUT
    end

    # hashable options
    %i[ssl http2_settings resolver_options pool_options].each do |option|
      class_eval(<<-OUT, __FILE__, __LINE__ + 1)
        # converts +v+ into an Hash before setting the +#{option}+ option.
        private def option_#{option}(value) # def option_ssl(v)
          Hash[value]
        end
      OUT
    end

    %i[
      request_class response_class headers_class request_body_class
      response_body_class connection_class http1_class http2_class
      resolver_native_class resolver_system_class resolver_https_class options_class pool_class
      io fallback_protocol debug debug_redact resolver_class
      compress_request_body decompress_response_body
      persistent close_on_fork
    ].each do |method_name|
      class_eval(<<-OUT, __FILE__, __LINE__ + 1)
        # sets +v+ as the value of the +#{method_name}+ option
        private def option_#{method_name}(v); v; end # private def option_smth(v); v; end
      OUT
    end

    def option_origin(value)
      URI(value)
    end

    def option_base_path(value)
      String(value)
    end

    def option_headers(value)
      value = value.dup if value.frozen?

      headers_class.new(value)
    end

    def option_timeout(value)
      timeout_hash = Hash[value]

      default_timeouts = DEFAULT_OPTIONS[:timeout]

      # Validate keys and values
      timeout_hash.each do |key, val|
        raise TypeError, "invalid timeout: :#{key}" unless default_timeouts.key?(key)

        next if val.nil?

        raise TypeError, ":#{key} must be numeric" unless val.is_a?(Numeric)
      end

      timeout_hash
    end

    def option_supported_compression_formats(value)
      Array(value).map(&:to_s)
    end

    def option_transport(value)
      transport = value.to_s
      raise TypeError, "#{transport} is an unsupported transport type" unless %w[unix].include?(transport)

      transport
    end

    def option_addresses(value)
      Array(value).map { |entry| Resolver::Entry.convert(entry) }
    end

    def option_ip_families(value)
      Array(value)
    end

    def option_resolver_class(resolver_type)
      case resolver_type
      when Symbol
        meth = :"resolver_#{resolver_type}_class"

        raise TypeError, ":resolver_class must be a supported type" unless respond_to?(meth)

        resolver_type
      when Class
        raise TypeError, ":resolver_class must be a subclass of `#{Resolver::Resolver}`" unless resolver_type < Resolver::Resolver

        resolver_type
      else
        raise TypeError, ":resolver_class must be a supported type"
      end
    end

    def option_resolver_cache(cache_type)
      if cache_type.is_a?(Symbol)
        raise TypeError, ":resolver_cache: #{cache_type} is invalid" unless RESOLVER_TYPES.include?(cache_type)

        require "httpx/resolver/cache/file" if cache_type == :file

      else
        unless cache_type.respond_to?(:resolve) &&
               cache_type.respond_to?(:get) &&
               cache_type.respond_to?(:set) &&
               cache_type.respond_to?(:evict)
          raise TypeError, ":resolver_cache must be a compatible resolver cache and implement #resolve, #get, #set and #evict"
        end
      end

      cache_type
    end

    # called after all options are initialized
    def do_initialize
      hs = @headers

      # initialized default request headers
      hs["user-agent"] = USER_AGENT unless hs.key?("user-agent")
      hs["accept"] = "*/*" unless hs.key?("accept")
      if hs.key?("range")
        hs.delete("accept-encoding")
      else
        hs["accept-encoding"] = supported_compression_formats unless hs.key?("accept-encoding")
      end
    end

    def access_option(obj, k, ivar_map)
      case obj
      when Hash
        obj[ivar_map[k]]
      else
        obj.instance_variable_get(k)
      end
    end

    # rubocop:disable Lint/UselessConstantScoping
    # these really need to be defined at the end of the class
    SET_TEMPORARY_NAME = ->(klass, pl = nil) do
      if klass.respond_to?(:set_temporary_name) # ruby 3.4 only
        name = klass.name || "#{klass.superclass.name}(plugin)"
        name = "#{name}/#{pl}" if pl
        klass.set_temporary_name(name)
      end
    end

    DEFAULT_OPTIONS = {
      :max_requests => Float::INFINITY,
      :debug => nil,
      :debug_level => (ENV["HTTPX_DEBUG"] || 1).to_i,
      :debug_redact => ENV.key?("HTTPX_DEBUG_REDACT"),
      :ssl => EMPTY_HASH,
      :http2_settings => { settings_enable_push: 0 }.freeze,
      :fallback_protocol => "http/1.1",
      :supported_compression_formats => %w[gzip deflate],
      :decompress_response_body => true,
      :compress_request_body => true,
      :timeout => {
        connect_timeout: CONNECT_TIMEOUT,
        settings_timeout: SETTINGS_TIMEOUT,
        close_handshake_timeout: CLOSE_HANDSHAKE_TIMEOUT,
        operation_timeout: OPERATION_TIMEOUT,
        keep_alive_timeout: KEEP_ALIVE_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        write_timeout: WRITE_TIMEOUT,
        request_timeout: REQUEST_TIMEOUT,
      }.freeze,
      :headers_class => Class.new(Headers, &SET_TEMPORARY_NAME),
      :headers => EMPTY_HASH,
      :window_size => WINDOW_SIZE,
      :buffer_size => BUFFER_SIZE,
      :body_threshold_size => MAX_BODY_THRESHOLD_SIZE,
      :request_class => Class.new(Request, &SET_TEMPORARY_NAME),
      :response_class => Class.new(Response, &SET_TEMPORARY_NAME),
      :request_body_class => Class.new(Request::Body, &SET_TEMPORARY_NAME),
      :response_body_class => Class.new(Response::Body, &SET_TEMPORARY_NAME),
      :pool_class => Class.new(Pool, &SET_TEMPORARY_NAME),
      :connection_class => Class.new(Connection, &SET_TEMPORARY_NAME),
      :http1_class => Class.new(Connection::HTTP1, &SET_TEMPORARY_NAME),
      :http2_class => Class.new(Connection::HTTP2, &SET_TEMPORARY_NAME),
      :resolver_native_class => Class.new(Resolver::Native, &SET_TEMPORARY_NAME),
      :resolver_system_class => Class.new(Resolver::System, &SET_TEMPORARY_NAME),
      :resolver_https_class => Class.new(Resolver::HTTPS, &SET_TEMPORARY_NAME),
      :options_class => Class.new(self, &SET_TEMPORARY_NAME),
      :transport => nil,
      :addresses => nil,
      :persistent => false,
      :resolver_class => (ENV["HTTPX_RESOLVER"] || :native).to_sym,
      :resolver_cache => (ENV["HTTPX_RESOLVER_CACHE"] || :memory).to_sym,
      :resolver_options => { cache: true }.freeze,
      :pool_options => EMPTY_HASH,
      :ip_families => nil,
      :close_on_fork => false,
    }.each_value(&:freeze).freeze
    # rubocop:enable Lint/UselessConstantScoping
  end
end
