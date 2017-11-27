# frozen_string_literal: true

module HTTPX
   class Headers
    EMPTY = [].freeze # :nodoc:

    # Matches valid header field name according to RFC.
    # @see http://tools.ietf.org/html/rfc7230#section-3.2
    COMPLIANT_NAME_RE = /^[A-Za-z0-9!#\$%&'*+\-.^_`|~]+$/

    def initialize(h = nil)
      @headers = {}
      return unless h
      h.each do |field, value|
        @headers[normalize(field)] = Array(value)
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

    # merges headers with another header-quack.
    # the merge rule is, if the header already exists,
    # ignore what the +other+ headers has. Otherwise, set
    #
    def merge(other)
      # TODO: deep-copy
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
      a = @headers[normalize(field)] || return
      a.join(",")
    end

    # sets +value+ (if not nil) as single value for the +field+ header.
    #
    def []=(field, value)
      return unless value
      val = case value
      when Array
        value.map { |f| String(f) }
      else
        [String(value)]
      end
      @headers[normalize(field)] = val 
    end

    # deletes all values associated with +field+ header.
    #
    def delete(field)
      canonical = normalize(field)
      @headers.delete(canonical) if @headers.key?(canonical)
    end

    # adds additional +value+ to the existing, for header +field+.
    #
    def add(field, value)
      @headers[normalize(field)] ||= []
      val = case value
      when Array
        value.map { |f| String(f) }
      else
        [String(value)]
      end
      @headers[normalize(field)] += val 
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
        next if value.empty?
        value.each do |val|
          yield(field, val)
        end
      end
      self
    end

    # the headers store in Hash format
    def to_hash
      Hash[to_a]
    end

    # the headers store in array of pairs format
    def to_a
      Array(each)
    end

    # headers as string
    def to_s
      @headers.to_s
    end

    def ==(other)
      to_hash == self.class.new(other).to_hash
    end

    # this is internal API and doesn't abide to other public API
    # guarantees, like normalizing strings.
    # Please do not use this outside of core!
    #
    def key?(normalized_key)
      @headers.key?(normalized_key)
    end

    # returns the values for the +field+ header in array format.
    # This method is more internal, and for this reason doesn't try
    # to "correct" the user input, i.e. it doesn't normalize the key.
    #
    def get(field)
      @headers[normalize(field)] || EMPTY
    end

    private

    # this method is only here because there's legacy around using explicit
    # canonical header fields (ex: Content-Length), although the spec states that the header
    # fields are case-insensitive.
    #
    # This only normalizes a +field+ if passed a canonical HTTP/1 header +field+.
    #
    def normalize(field)
      normalized = String(field).downcase

      return normalized if normalized =~ COMPLIANT_NAME_RE

      raise HeaderError, "Invalid HTTP header field name: #{field.inspect}"
    end
  end
end

