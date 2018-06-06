# frozen_string_literal: true

module HTTPX
  class Options
    MAX_CONCURRENT_REQUESTS = 100
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

        attr_accessor name
        protected :"#{name}="

        define_method(:"with_#{name}") do |value|
          dup { |opts| opts.send(:"#{name}=", instance_exec(value, &interpreter)) }
        end
      end
    end

    def initialize(options = {})
      defaults = {
        :debug                    => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
        :debug_level              => (ENV["HTTPX_DEBUG"] || 1).to_i,
        :ssl                      => {},
        :http2_settings           => { settings_enable_push: 0 },
        :fallback_protocol        => "http/1.1",
        :timeout                  => Timeout.new,
        :headers                  => {},
        :max_concurrent_requests  => MAX_CONCURRENT_REQUESTS,
        :window_size              => WINDOW_SIZE,
        :body_threshold_size      => MAX_BODY_THRESHOLD_SIZE,
        :request_class            => Class.new(Request),
        :response_class           => Class.new(Response),
        :headers_class            => Class.new(Headers),
        :request_body_class       => Class.new(Request::Body),
        :response_body_class      => Class.new(Response::Body),
      }

      defaults.merge!(options)
      defaults[:headers] = Headers.new(defaults[:headers])
      defaults.each { |(k, v)| self[k] = v }
    end

    def_option(:headers) do |headers|
      self.headers.merge(headers)
    end

    def_option(:timeout) do |opts|
      self.timeout = Timeout.new(opts)
    end

    def_option(:max_concurrent_requests) do |num|
      max = Integer(num)
      raise Error, ":max_concurrent_requests must be positive" unless max.positive?
      self.max_concurrent_requests = max
    end

    def_option(:window_size) do |num|
      self.window_size = Integer(num)
    end

    def_option(:body_threshold_size) do |num|
      self.body_threshold_size = Integer(num)
    end

    %w[
      params form json body
      follow ssl http2_settings
      request_class response_class headers_class request_body_class response_body_class
      io fallback_protocol debug debug_level
    ].each do |method_name|
      def_option(method_name)
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

    def dup
      dupped = super
      dupped.headers             = headers.dup
      dupped.ssl                 = ssl.dup
      dupped.request_class       = request_class.dup
      dupped.response_class      = response_class.dup
      dupped.headers_class       = headers_class.dup
      dupped.request_body_class  = request_body_class.dup
      dupped.response_body_class = response_body_class.dup
      yield(dupped) if block_given?
      dupped
    end

    protected

    def []=(option, val)
      send(:"#{option}=", val)
    end
  end
end
