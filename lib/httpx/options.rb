# frozen_string_literal: true

module HTTPX
  class Options
    WINDOW_SIZE = 1 << 14 # 16K
    MAX_BODY_THRESHOLD_SIZE = (1 << 10) * 112 # 112K
    CONNECT_TIMEOUT = 60
    OPERATION_TIMEOUT = 60
    KEEP_ALIVE_TIMEOUT = 20

    DEFAULT_OPTIONS = {
      :debug => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :debug_level => (ENV["HTTPX_DEBUG"] || 1).to_i,
      :ssl => {},
      :http2_settings => { settings_enable_push: 0 },
      :fallback_protocol => "http/1.1",
      :timeout => {
        connect_timeout: CONNECT_TIMEOUT,
        operation_timeout: OPERATION_TIMEOUT,
        keep_alive_timeout: KEEP_ALIVE_TIMEOUT,
      },
      :headers => {},
      :window_size => WINDOW_SIZE,
      :body_threshold_size => MAX_BODY_THRESHOLD_SIZE,
      :request_class => Class.new(Request),
      :response_class => Class.new(Response),
      :headers_class => Class.new(Headers),
      :request_body_class => Class.new(Request::Body),
      :response_body_class => Class.new(Response::Body),
      :connection_class => Class.new(Connection),
      :transport => nil,
      :transport_options => nil,
      :addresses => nil,
      :persistent => false,
      :resolver_class => (ENV["HTTPX_RESOLVER"] || :native).to_sym,
      :resolver_options => { cache: true },
    }.freeze

    class << self
      def new(options = {})
        # let enhanced options go through
        return options if self == Options && options.class > self
        return options if options.is_a?(self)

        super
      end

      def def_option(name, layout = nil, &interpreter)
        attr_reader name

        if layout
          class_eval(<<-OUT, __FILE__, __LINE__ + 1)
            def #{name}=(value)
              return if value.nil?

              value = begin
                #{layout}
              end

              @#{name} = value
            end
          OUT

        elsif interpreter
          define_method(:"#{name}=") do |value|
            return if value.nil?

            instance_variable_set(:"@#{name}", instance_exec(value, &interpreter))
          end
        else
          attr_writer name
        end

        protected :"#{name}="
      end
    end

    def initialize(options = {})
      defaults = DEFAULT_OPTIONS.merge(options)
      defaults.each do |(k, v)|
        next if v.nil?

        begin
          __send__(:"#{k}=", v)
        rescue NoMethodError
          raise Error, "unknown option: #{k}"
        end
      end
    end

    def_option(:headers, <<-OUT)
      if self.headers
        self.headers.merge(value)
      else
        Headers.new(value)
      end
    OUT

    def_option(:timeout, <<-OUT)
      timeouts = Hash[value]

      if timeouts.key?(:loop_timeout)
        warn ":loop_timeout is deprecated, use :operation_timeout instead"
        timeouts[:operation_timeout] = timeouts.delete(:loop_timeout)
      end

      timeouts
    OUT

    def_option(:max_concurrent_requests, <<-OUT)
      raise Error, ":max_concurrent_requests must be positive" unless value.positive?

      value
    OUT

    def_option(:max_requests, <<-OUT)
      raise Error, ":max_requests must be positive" unless value.positive?

      value
    OUT

    def_option(:window_size, <<-OUT)
      Integer(value)
    OUT

    def_option(:body_threshold_size, <<-OUT)
      Integer(value)
    OUT

    def_option(:transport, <<-OUT)
      transport = value.to_s
      raise Error, "\#{transport} is an unsupported transport type" unless IO.registry.key?(transport)

      transport
    OUT

    def_option(:addresses, <<-OUT)
      Array(value)
    OUT

    %w[
      params form json body ssl http2_settings
      request_class response_class headers_class request_body_class response_body_class connection_class
      io fallback_protocol debug debug_level transport_options resolver_class resolver_options
      persistent
    ].each do |method_name|
      def_option(method_name)
    end

    REQUEST_IVARS = %i[@params @form @json @body].freeze

    def ==(other)
      ivars = instance_variables | other.instance_variables
      ivars.all? do |ivar|
        case ivar
        when :@headers
          headers = instance_variable_get(ivar)
          headers.same_headers?(other.instance_variable_get(ivar))
        when *REQUEST_IVARS
          true
        else
          instance_variable_get(ivar) == other.instance_variable_get(ivar)
        end
      end
    end

    def merge(other)
      h2 = other.to_hash
      return self if h2.empty?

      h1 = to_hash

      return self if h1 == h2

      merged = h1.merge(h2) do |k, v1, v2|
        case k
        when :headers, :ssl, :http2_settings, :timeout
          v1.merge(v2)
        else
          v2
        end
      end

      self.class.new(merged)
    end

    def to_hash
      hash_pairs = instance_variables.map do |ivar|
        [ivar[1..-1].to_sym, instance_variable_get(ivar)]
      end
      Hash[hash_pairs]
    end

    def initialize_dup(other)
      self.headers             = other.headers.dup
      self.ssl                 = other.ssl.dup
      self.request_class       = other.request_class.dup
      self.response_class      = other.response_class.dup
      self.headers_class       = other.headers_class.dup
      self.request_body_class  = other.request_body_class.dup
      self.response_body_class = other.response_body_class.dup
      self.connection_class    = other.connection_class.dup
    end

    def freeze
      super

      headers.freeze
      ssl.freeze
      request_class.freeze
      response_class.freeze
      headers_class.freeze
      request_body_class.freeze
      response_body_class.freeze
      connection_class.freeze
    end
  end
end
