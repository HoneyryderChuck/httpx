# frozen_string_literal: true

module HTTPX
  class Options
    WINDOW_SIZE = 1 << 14 # 16K
    MAX_BODY_THRESHOLD_SIZE = (1 << 10) * 112 # 112K

    class << self
      def inherited(klass)
        super
        klass.instance_variable_set(:@defined_options, @defined_options.dup)
      end

      def new(options = {})
        # let enhanced options go through
        return options if self == Options && options.class > self
        return options if options.is_a?(self)

        super
      end

      def defined_options
        @defined_options ||= []
      end

      def def_option(name, &interpreter)
        defined_options << name.to_sym
        interpreter ||= ->(v) { v }

        attr_reader name

        define_method(:"#{name}=") do |value|
          return if value.nil?

          instance_variable_set(:"@#{name}", instance_exec(value, &interpreter))
        end

        protected :"#{name}="

        define_method(:"with_#{name}") do |value|
          other = dup
          other.send(:"#{name}=", other.instance_exec(value, &interpreter))
          other
        end
      end
    end

    def initialize(options = {})
      defaults = {
        :debug => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
        :debug_level => (ENV["HTTPX_DEBUG"] || 1).to_i,
        :ssl => {},
        :http2_settings => { settings_enable_push: 0 },
        :fallback_protocol => "http/1.1",
        :timeout => Timeout.new,
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
        :persistent => false,
        :resolver_class => (ENV["HTTPX_RESOLVER"] || :native).to_sym,
        :resolver_options => { cache: true },
      }

      defaults.merge!(options)
      defaults[:headers] = Headers.new(defaults[:headers])
      defaults.each do |(k, v)|
        __send__(:"#{k}=", v)
      end
    end

    def_option(:headers) do |headers|
      if self.headers
        self.headers.merge(headers)
      else
        headers
      end
    end

    def_option(:timeout) do |opts|
      Timeout.new(opts)
    end

    def_option(:max_concurrent_requests) do |num|
      raise Error, ":max_concurrent_requests must be positive" unless num.positive?

      num
    end

    def_option(:max_requests) do |num|
      raise Error, ":max_requests must be positive" unless num.positive?

      num
    end

    def_option(:window_size) do |num|
      Integer(num)
    end

    def_option(:body_threshold_size) do |num|
      Integer(num)
    end

    def_option(:transport) do |tr|
      transport = tr.to_s
      raise Error, "#{transport} is an unsupported transport type" unless IO.registry.key?(transport)

      transport
    end

    %w[
      params form json body
      follow ssl http2_settings
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
      h1 = to_hash
      h2 = other.to_hash

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
      hash_pairs = self.class
                       .defined_options
                       .flat_map { |opt_name| [opt_name, send(opt_name)] }
      Hash[*hash_pairs]
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
