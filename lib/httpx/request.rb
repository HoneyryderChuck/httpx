# frozen_string_literal: true

require "delegate"
require "forwardable"

module HTTPX
  class Request
    extend Forwardable
    include Callbacks
    using URIExtensions

    USER_AGENT = "httpx.rb/#{VERSION}"

    attr_reader :verb, :uri, :headers, :body, :state, :options, :response

    # Exception raised during enumerable body writes
    attr_reader :drain_error

    def_delegator :@body, :empty?

    def initialize(verb, uri, options = {})
      if verb.is_a?(Symbol)
        warn "DEPRECATION WARNING: Using symbols for `verb` is deprecated, and will not be supported in httpx 1.0. " \
             "Use \"#{verb.to_s.upcase}\" instead."
      end
      @verb    = verb.to_s.upcase
      @options = Options.new(options)
      @uri     = Utils.to_uri(uri)
      if @uri.relative?
        origin = @options.origin
        raise(Error, "invalid URI: #{@uri}") unless origin

        base_path = @options.base_path

        @uri = origin.merge("#{base_path}#{@uri}")
      end

      @headers = @options.headers_class.new(@options.headers)
      @headers["user-agent"] ||= USER_AGENT
      @headers["accept"]     ||= "*/*"

      @body = @options.request_body_class.new(@headers, @options)
      @state = :idle
    end

    def read_timeout
      @options.timeout[:read_timeout]
    end

    def write_timeout
      @options.timeout[:write_timeout]
    end

    def request_timeout
      @options.timeout[:request_timeout]
    end

    def trailers?
      defined?(@trailers)
    end

    def trailers
      @trailers ||= @options.headers_class.new
    end

    def interests
      return :r if @state == :done || @state == :expect

      :w
    end

    if RUBY_VERSION < "2.2"
      URIParser = URI::DEFAULT_PARSER

      def initialize_with_escape(verb, uri, options = {})
        initialize_without_escape(verb, URIParser.escape(uri.to_s), options)
      end
      alias_method :initialize_without_escape, :initialize
      alias_method :initialize, :initialize_with_escape
    end

    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    def scheme
      @uri.scheme
    end

    def response=(response)
      return unless response

      if response.is_a?(Response) && response.status == 100 && @headers.key?("expect")
        @informational_status = response.status
        return
      end
      @response = response
    end

    def path
      path = uri.path.dup
      path =  +"" if path.nil?
      path << "/" if path.empty?
      path << "?#{query}" unless query.empty?
      path
    end

    # https://bugs.ruby-lang.org/issues/15278
    def authority
      @uri.authority
    end

    # https://bugs.ruby-lang.org/issues/15278
    def origin
      @uri.origin
    end

    def query
      return @query if defined?(@query)

      query = []
      if (q = @options.params)
        query << Transcoder::Form.encode(q)
      end
      query << @uri.query if @uri.query
      @query = query.join("&")
    end

    def drain_body
      return nil if @body.nil?

      @drainer ||= @body.each
      chunk = @drainer.next
      chunk.dup
    rescue StopIteration
      nil
    rescue StandardError => e
      @drain_error = e
      nil
    end

    # :nocov:
    def inspect
      "#<HTTPX::Request:#{object_id} " \
        "#{@verb} " \
        "#{uri} " \
        "@headers=#{@headers} " \
        "@body=#{@body}>"
    end
    # :nocov:

    class Body < SimpleDelegator
      class << self
        def new(_, options)
          return options.body if options.body.is_a?(self)

          super
        end
      end

      def initialize(headers, options)
        @headers = headers
        @body = initialize_body(options)
        return if @body.nil?

        @headers["content-type"] ||= @body.content_type
        @headers["content-length"] = @body.bytesize unless unbounded_body?
        super(@body)
      end

      def each(&block)
        return enum_for(__method__) unless block
        return if @body.nil?

        body = stream(@body)
        if body.respond_to?(:read)
          ::IO.copy_stream(body, ProcIO.new(block))
        elsif body.respond_to?(:each)
          body.each(&block)
        else
          block[body.to_s]
        end
      end

      def rewind
        return if empty?

        @body.rewind if @body.respond_to?(:rewind)
      end

      def empty?
        return true if @body.nil?
        return false if chunked?

        @body.bytesize.zero?
      end

      def bytesize
        return 0 if @body.nil?

        @body.bytesize
      end

      def stream(body)
        encoded = body
        encoded = Transcoder::Chunker.encode(body.enum_for(:each)) if chunked?
        encoded
      end

      def unbounded_body?
        return @unbounded_body if defined?(@unbounded_body)

        @unbounded_body = !@body.nil? && (chunked? || @body.bytesize == Float::INFINITY)
      end

      def chunked?
        @headers["transfer-encoding"] == "chunked"
      end

      def chunk!
        @headers.add("transfer-encoding", "chunked")
      end

      # :nocov:
      def inspect
        "#<HTTPX::Request::Body:#{object_id} " \
          "#{unbounded_body? ? "stream" : "@bytesize=#{bytesize}"}>"
      end
      # :nocov:

      private

      def initialize_body(options)
        if options.body
          Transcoder::Body.encode(options.body)
        elsif options.form
          Transcoder::Form.encode(options.form)
        elsif options.json
          Transcoder::JSON.encode(options.json)
        elsif options.xml
          Transcoder::Xml.encode(options.xml)
        end
      end
    end

    def transition(nextstate)
      case nextstate
      when :idle
        @body.rewind
        @response = nil
        @drainer = nil
      when :headers
        return unless @state == :idle
      when :body
        return unless @state == :headers ||
                      @state == :expect

        if @headers.key?("expect")
          if @informational_status && @informational_status == 100
            # check for 100 Continue response, and deallocate the var
            # if @informational_status == 100
            #   @response = nil
            # end
          else
            return if @state == :expect # do not re-set it

            nextstate = :expect
          end
        end
      when :trailers
        return unless @state == :body
      when :done
        return if @state == :expect
      end
      @state = nextstate
      emit(@state, self)
      nil
    end

    def expects?
      @headers["expect"] == "100-continue" && @informational_status == 100 && !@response
    end

    class ProcIO
      def initialize(block)
        @block = block
      end

      def write(data)
        @block.call(data.dup)
        data.bytesize
      end
    end
  end
end
