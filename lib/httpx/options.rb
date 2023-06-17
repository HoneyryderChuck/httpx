# frozen_string_literal: true

require "socket"

module HTTPX
  class Options
    BUFFER_SIZE = 1 << 14
    WINDOW_SIZE = 1 << 14 # 16K
    MAX_BODY_THRESHOLD_SIZE = (1 << 10) * 112 # 112K
    CONNECT_TIMEOUT = 60
    OPERATION_TIMEOUT = 60
    KEEP_ALIVE_TIMEOUT = 20
    SETTINGS_TIMEOUT = 10
    READ_TIMEOUT = WRITE_TIMEOUT = REQUEST_TIMEOUT = Float::INFINITY

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
      :debug => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :debug_level => (ENV["HTTPX_DEBUG"] || 1).to_i,
      :ssl => {},
      :http2_settings => { settings_enable_push: 0 },
      :fallback_protocol => "http/1.1",
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
      :transport_options => nil,
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

      def def_option(optname, *args, &block)
        if args.empty? && !block
          class_eval(<<-OUT, __FILE__, __LINE__ + 1)
            def option_#{optname}(v); v; end # def option_smth(v); v; end
          OUT
          return
        end

        deprecated_def_option(optname, *args, &block)
      end

      def deprecated_def_option(optname, layout = nil, &interpreter)
        warn "DEPRECATION WARNING: using `def_option(#{optname})` for setting options is deprecated. " \
             "Define module OptionsMethods and `def option_#{optname}(val)` instead."

        if layout
          class_eval(<<-OUT, __FILE__, __LINE__ + 1)
            def option_#{optname}(value)  # def option_origin(v)
              #{layout}                   #   URI(v)
            end                           # end
          OUT
        elsif interpreter
          define_method(:"option_#{optname}") do |value|
            instance_exec(value, &interpreter)
          end
        end
      end
    end

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
      timeouts = Hash[value]

      if timeouts.key?(:loop_timeout)
        warn ":loop_timeout is deprecated, use :operation_timeout instead"
        timeouts[:operation_timeout] = timeouts.delete(:loop_timeout)
      end

      timeouts
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
      Integer(value)
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
      io fallback_protocol debug debug_level transport_options resolver_class resolver_options
      persistent
    ].each do |method_name|
      def_option(method_name)
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
