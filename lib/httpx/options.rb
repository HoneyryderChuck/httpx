# frozen_string_literal: true

module HTTPX
  class Options
    MAX_CONCURRENT_REQUESTS = 100
    MAX_RETRIES = 3

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

      protected

      def def_option(name, &interpreter)
        defined_options << name.to_sym
        interpreter ||= lambda { |v| v }

        attr_accessor name
        protected :"#{name}="

        define_method(:"with_#{name}") do |value|
          dup { |opts| opts.send(:"#{name}=", instance_exec(value, &interpreter)) }
        end
      end
    end

    def initialize(options = {})
      defaults = {
        :proxy                    => {},
        :ssl                      => {},
        :timeout                  => Timeout.by(:null), 
        :headers                  => {},
        :cookies                  => {},
        :max_concurrent_requests  => MAX_CONCURRENT_REQUESTS,
        :max_retries              => MAX_RETRIES,
        :request_class            => Class.new(Request),
        :response_class           => Class.new(Response),
        :headers_class            => Class.new(Headers),
      }

      defaults.merge!(options)
      defaults[:headers] = Headers.new(defaults[:headers])
      defaults.each { |(k, v)| self[k] = v }
    end

    def_option(:headers) do |headers|
      self.headers.merge(headers)
    end

    def_option(:cookies) do |cookies|
      cookies.each_with_object self.cookies.dup do |(k, v), jar|
        cookie = k.is_a?(Cookie) ? k : Cookie.new(k.to_s, v.to_s)
        jar[cookie.name] = cookie.cookie_value
      end
    end

    def_option(:timeout) do |type, opts|
      self.timeout = Timeout.by(type, opts)
    end

    def_option(:max_concurrent_requests) do |num|
      max = Integer(num)
      raise Error, ":max_concurrent_requests must be positive" unless max.positive?
      self.max_concurrent_requests = max
    end

    %w[
      params form json body
      proxy follow ssl max_retries
      request_class response_class headers_class
    ].each do |method_name|
      def_option(method_name)
    end

    def merge(other)
      h1 = to_hash
      h2 = other.to_hash

      merged = h1.merge(h2) do |k, v1, v2|
        case k
        when :headers
          v1.merge(v2)
        else
          v2
        end
      end

      self.class.new(merged)
    end

    def to_hash
      hash_pairs = self.class.
                   defined_options.
                   flat_map { |opt_name| [opt_name, send(opt_name)] }
      Hash[*hash_pairs]
    end

    def dup
      dupped = super
      yield(dupped) if block_given?
      dupped
    end

    protected

    def []=(option, val)
      send(:"#{option}=", val)
    end
  end
end
