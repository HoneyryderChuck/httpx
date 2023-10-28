# frozen_string_literal: true

require "socket"

module HTTPX
  # Contains a set of options which are passed and shared across from session to its requests or
  # responses.
  class Options
    BUFFER_SIZE = 1 << 14
    WINDOW_SIZE = 1 << 14 # 16K
    MAX_BODY_THRESHOLD_SIZE = (1 << 10) * 112 # 112K
    KEEP_ALIVE_TIMEOUT = 20
    SETTINGS_TIMEOUT = 10
    CONNECT_TIMEOUT = READ_TIMEOUT = WRITE_TIMEOUT = 60
    REQUEST_TIMEOUT = OPERATION_TIMEOUT = nil

    # https://github.com/ruby/resolv/blob/095f1c003f6073730500f02acbdbc55f83d70987/lib/resolv.rb#L408
    ip_address_families = begin
      list = Socket.ip_address_list
      if list.any? { |a| a.ipv6? && !a.ipv6_loopback? && !a.ipv6_linklocal? && !a.ipv6_unique_local? }
        [Socket::AF_INET6, Socket::AF_INET]
      else
        [Socket::AF_INET]
      end
    rescue NotImplementedError
      [Socket::AF_INET]
    end

    DEFAULT_OPTIONS = {
      :max_requests => Float::INFINITY,
      :debug => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :debug_level => (ENV["HTTPX_DEBUG"] || 1).to_i,
      :ssl => {},
      :http2_settings => { settings_enable_push: 0 },
      :fallback_protocol => "http/1.1",
      :supported_compression_formats => %w[gzip deflate],
      :decompress_response_body => true,
      :compress_request_body => true,
      :timeout => {
        connect_timeout: CONNECT_TIMEOUT,
        settings_timeout: SETTINGS_TIMEOUT,
        operation_timeout: OPERATION_TIMEOUT,
        keep_alive_timeout: KEEP_ALIVE_TIMEOUT,
        read_timeout: READ_TIMEOUT,
        write_timeout: WRITE_TIMEOUT,
        request_timeout: REQUEST_TIMEOUT,
      },
      :headers => {},
      :window_size => WINDOW_SIZE,
      :buffer_size => BUFFER_SIZE,
      :body_threshold_size => MAX_BODY_THRESHOLD_SIZE,
      :request_class => Class.new(Request),
      :response_class => Class.new(Response),
      :headers_class => Class.new(Headers),
      :request_body_class => Class.new(Request::Body),
      :response_body_class => Class.new(Response::Body),
      :connection_class => Class.new(Connection),
      :options_class => Class.new(self),
      :transport => nil,
      :addresses => nil,
      :persistent => false,
      :resolver_class => (ENV["HTTPX_RESOLVER"] || :native).to_sym,
      :resolver_options => { cache: true },
      :ip_families => ip_address_families,
    }.freeze

    class << self
      def new(options = {})
        # let enhanced options go through
        return options if self == Options && options.class < self
        return options if options.is_a?(self)

        super
      end

      def method_added(meth)
        super

        return unless meth =~ /^option_(.+)$/

        optname = Regexp.last_match(1).to_sym

        attr_reader(optname)
      end
    end

    # creates a new options instance from a given hash, which optionally define the following:
    #
    # :debug :: an object which log messages are written to (must respond to <tt><<</tt>)
    # :debug_level :: the log level of messages (can be 1, 2, or 3).
    # :ssl :: a hash of options which can be set as params of OpenSSL::SSL::SSLContext (see HTTPX::IO::SSL)
    # :http2_settings :: a hash of options to be passed to a HTTP2Next::Connection (ex: <tt>{ max_concurrent_streams: 2 }</tt>)
    # :fallback_protocol :: version of HTTP protocol to use by default in the absence of protocol negotiation
    #                       like ALPN (defaults to <tt>"http/1.1"</tt>)
    # :supported_compression_formats :: list of compressions supported by the transcoder layer (defaults to <tt>%w[gzip deflate]</tt>).
    # :decompress_response_body :: whether to auto-decompress response body (defaults to <tt>true</tt>).
    # :compress_request_body :: whether to auto-decompress response body (defaults to <tt>true</tt>)
    # :timeout :: hash of timeout configurations (supports <tt>:connect_timeout</tt>, <tt>:settings_timeout</tt>,
    #             <tt>:operation_timeout</tt>, <tt>:keep_alive_timeout</tt>,  <tt>:read_timeout</tt>,  <tt>:write_timeout</tt>
    #            and <tt>:request_timeout</tt>
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
    # :options_class :: class used to instantiate options
    # :transport :: type of transport to use (set to "unix" for UNIX sockets)
    # :addresses :: bucket of peer addresses (can be a list of IP addresses, a hash of domain to list of adddresses;
    #               paths should be used for UNIX sockets instead)
    # :io :: open socket, or domain/ip-to-socket hash, which requests should be sent to
    # :persistent :: whether to persist connections in between requests (defaults to <tt>true</tt>)
    # :resolver_class :: which resolver to use (defaults to <tt>:native</tt>, can also be <tt>:system<tt> for
    #                    using getaddrinfo or <tt>:https</tt> for DoH resolver, or a custom class)
    # :resolver_options :: hash of options passed to the resolver
    # :ip_families :: which socket families are supported (system-dependent)
    # :origin :: HTTP origin to set on requests with relative path (ex: "https://api.serv.com")
    # :base_path :: path to prefix given relative paths with (ex: "/v2")
    # :max_concurrent_requests :: max number of requests which can be set concurrently
    # :max_requests :: max number of requests which can be made on socket before it reconnects.
    # :params :: hash or array of key-values which will be encoded and set in the query string of request uris.
    # :form :: hash of array of key-values which will be form-or-multipart-encoded in requests body payload.
    # :json :: hash of array of key-values which will be JSON-encoded in requests body payload.
    # :xml :: Nokogiri XML nodes which will be encoded in requests body payload.
    #
    # This list of options are enhanced with each loaded plugin, see the plugin docs for details.
    def initialize(options = {})
      do_initialize(options)
      freeze
    end

    def freeze
      super
      @origin.freeze
      @base_path.freeze
      @timeout.freeze
      @headers.freeze
      @addresses.freeze
      @supported_compression_formats.freeze
    end

    def option_origin(value)
      URI(value)
    end

    def option_base_path(value)
      String(value)
    end

    def option_headers(value)
      Headers.new(value)
    end

    def option_timeout(value)
      Hash[value]
    end

    def option_supported_compression_formats(value)
      Array(value).map(&:to_s)
    end

    def option_max_concurrent_requests(value)
      raise TypeError, ":max_concurrent_requests must be positive" unless value.positive?

      value
    end

    def option_max_requests(value)
      raise TypeError, ":max_requests must be positive" unless value.positive?

      value
    end

    def option_window_size(value)
      value = Integer(value)

      raise TypeError, ":window_size must be positive" unless value.positive?

      value
    end

    def option_buffer_size(value)
      value = Integer(value)

      raise TypeError, ":buffer_size must be positive" unless value.positive?

      value
    end

    def option_body_threshold_size(value)
      bytes = Integer(value)
      raise TypeError, ":body_threshold_size must be positive" unless bytes.positive?

      bytes
    end

    def option_transport(value)
      transport = value.to_s
      raise TypeError, "#{transport} is an unsupported transport type" unless %w[unix].include?(transport)

      transport
    end

    def option_addresses(value)
      Array(value)
    end

    def option_ip_families(value)
      Array(value)
    end

    %i[
      params form json xml body ssl http2_settings
      request_class response_class headers_class request_body_class
      response_body_class connection_class options_class
      io fallback_protocol debug debug_level resolver_class resolver_options
      compress_request_body decompress_response_body
      persistent
    ].each do |method_name|
      class_eval(<<-OUT, __FILE__, __LINE__ + 1)
        def option_#{method_name}(v); v; end # def option_smth(v); v; end
      OUT
    end

    REQUEST_IVARS = %i[@params @form @xml @json @body].freeze
    private_constant :REQUEST_IVARS

    def ==(other)
      ivars = instance_variables | other.instance_variables
      ivars.all? do |ivar|
        case ivar
        when :@headers
          # currently, this is used to pick up an available matching connection.
          # the headers do not play a role, as they are relevant only for the request.
          true
        when *REQUEST_IVARS
          true
        else
          instance_variable_get(ivar) == other.instance_variable_get(ivar)
        end
      end
    end

    def merge(other)
      raise ArgumentError, "#{other} is not a valid set of options" unless other.respond_to?(:to_hash)

      h2 = other.to_hash
      return self if h2.empty?

      h1 = to_hash

      return self if h1 >= h2

      merged = h1.merge(h2) do |_k, v1, v2|
        if v1.respond_to?(:merge) && v2.respond_to?(:merge)
          v1.merge(v2)
        else
          v2
        end
      end

      self.class.new(merged)
    end

    def to_hash
      instance_variables.each_with_object({}) do |ivar, hs|
        hs[ivar[1..-1].to_sym] = instance_variable_get(ivar)
      end
    end

    def initialize_dup(other)
      instance_variables.each do |ivar|
        instance_variable_set(ivar, other.instance_variable_get(ivar).dup)
      end
    end

    private

    def do_initialize(options = {})
      defaults = DEFAULT_OPTIONS.merge(options)
      defaults.each do |k, v|
        next if v.nil?

        begin
          value = __send__(:"option_#{k}", v)
          instance_variable_set(:"@#{k}", value)
        rescue NoMethodError
          raise Error, "unknown option: #{k}"
        end
      end
    end
  end
end
