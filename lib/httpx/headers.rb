# frozen_string_literal: true

module HTTPX
  class Headers
    EMPTY = [].freeze

    class << self
      def new(headers = nil)
        return headers if headers.is_a?(self)

        super
      end
    end

    def initialize(headers = nil)
      @headers = {}
      return unless headers

      headers.each do |field, value|
        array_value(value).each do |v|
          add(downcased(field), v)
        end
      end
    end

    # cloned initialization
    def initialize_clone(orig)
      super
      @headers = orig.instance_variable_get(:@headers).clone
    end

    # dupped initialization
    def initialize_dup(orig)
      super
      @headers = orig.instance_variable_get(:@headers).dup
    end

    # freezes the headers hash
    def freeze
      @headers.freeze
      super
    end

    def same_headers?(headers)
      @headers.empty? || begin
        headers.each do |k, v|
          return false unless v == self[k]
        end
        true
      end
    end

    # merges headers with another header-quack.
    # the merge rule is, if the header already exists,
    # ignore what the +other+ headers has. Otherwise, set
    #
    def merge(other)
      headers = dup
      other.each do |field, value|
        headers[field] = value
      end
      headers
    end

    # returns the comma-separated values of the header field
    # identified by +field+, or nil otherwise.
    #
    def [](field)
      a = @headers[downcased(field)] || return
      a.join(", ")
    end

    # sets +value+ (if not nil) as single value for the +field+ header.
    #
    def []=(field, value)
      return unless value

      @headers[downcased(field)] = array_value(value)
    end

    # deletes all values associated with +field+ header.
    #
    def delete(field)
      canonical = downcased(field)
      @headers.delete(canonical) if @headers.key?(canonical)
    end

    # adds additional +value+ to the existing, for header +field+.
    #
    def add(field, value)
      (@headers[downcased(field)] ||= []) << String(value)
    end

    # helper to be used when adding an header field as a value to another field
    #
    #     h2_headers.add_header("vary", "accept-encoding")
    #     h2_headers["vary"] #=> "accept-encoding"
    #     h1_headers.add_header("vary", "accept-encoding")
    #     h1_headers["vary"] #=> "Accept-Encoding"
    #
    alias_method :add_header, :add

    # returns the enumerable headers store in pairs of header field + the values in
    # the comma-separated string format
    #
    def each
      return enum_for(__method__) { @headers.size } unless block_given?

      @headers.each do |field, value|
        yield(field, value.join(", ")) unless value.empty?
      end
    end

    def ==(other)
      other == to_hash
    end

    # the headers store in Hash format
    def to_hash
      Hash[to_a]
    end
    alias_method :to_h, :to_hash

    # the headers store in array of pairs format
    def to_a
      Array(each)
    end

    # headers as string
    def to_s
      @headers.to_s
    end

    # :nocov:
    def inspect
      to_hash.inspect
    end
    # :nocov:

    # this is internal API and doesn't abide to other public API
    # guarantees, like downcasing strings.
    # Please do not use this outside of core!
    #
    def key?(downcased_key)
      @headers.key?(downcased_key)
    end

    # returns the values for the +field+ header in array format.
    # This method is more internal, and for this reason doesn't try
    # to "correct" the user input, i.e. it doesn't downcase the key.
    #
    def get(field)
      @headers[field] || EMPTY
    end

    private

    def array_value(value)
      case value
      when Array
        value.map { |val| String(val).strip }
      else
        [String(value).strip]
      end
    end

    def downcased(field)
      String(field).downcase
    end
  end
end
