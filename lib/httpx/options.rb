# frozen_string_literal: true

module HTTPX
  class Options
    KEEP_ALIVE_TIMEOUT = 5
    OPERATION_TIMEOUT = 5
    CONNECT_TIMEOUT = 5

    class << self
      def new(options = {})
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
        :proxy              => {},
        :ssl                => {},
        :timeout            => Timeout.by(:null), 
        :headers            => {},
        :cookies            => {},
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

    %w[
      proxy params form json body follow 
      ssl
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
