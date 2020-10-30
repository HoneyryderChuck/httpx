# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Request
    extend Forwardable
    include Callbacks
    using URIExtensions

    METHODS = [
      # RFC 2616: Hypertext Transfer Protocol -- HTTP/1.1
      :options, :get, :head, :post, :put, :delete, :trace, :connect,

      # RFC 2518: HTTP Extensions for Distributed Authoring -- WEBDAV
      :propfind, :proppatch, :mkcol, :copy, :move, :lock, :unlock,

      # RFC 3648: WebDAV Ordered Collections Protocol
      :orderpatch,

      # RFC 3744: WebDAV Access Control Protocol
      :acl,

      # RFC 6352: vCard Extensions to WebDAV -- CardDAV
      :report,

      # RFC 5789: PATCH Method for HTTP
      :patch,

      # draft-reschke-webdav-search: WebDAV Search
      :search
    ].freeze

    USER_AGENT = "httpx.rb/#{VERSION}"

    attr_reader :verb, :uri, :headers, :body, :state

    attr_reader :options, :response

    def_delegator :@body, :empty?

    def_delegator :@body, :chunk!

    def initialize(verb, uri, options = {})
      @verb    = verb.to_s.downcase.to_sym
      @uri     = URI(uri)
      @options = Options.new(options)

      raise(Error, "unknown method: #{verb}") unless METHODS.include?(@verb)

      @headers = @options.headers_class.new(@options.headers)
      @headers["user-agent"] ||= USER_AGENT
      @headers["accept"]     ||= "*/*"

      @body = @options.request_body_class.new(@headers, @options)
      @state = :idle
    end

    def interests
      return :r if @state == :done || @state == :expect

      :w
    end

    if RUBY_VERSION < "2.2"
      # rubocop: disable Lint/UriEscapeUnescape:
      def initialize_with_escape(verb, uri, options = {})
        initialize_without_escape(verb, URI.escape(uri.to_s), options)
      end
      alias_method :initialize_without_escape, :initialize
      alias_method :initialize, :initialize_with_escape
      # rubocop: enable Lint/UriEscapeUnescape:
    end

    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    def scheme
      @uri.scheme
    end

    def response=(response)
      return unless response

      @response = response
    end

    def path
      path = uri.path.dup
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
        query << URI.encode_www_form(q)
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
    end

    # :nocov:
    def inspect
      "#<HTTPX::Request:#{object_id} " \
      "#{@verb.to_s.upcase} " \
      "#{uri} " \
      "@headers=#{@headers} " \
      "@body=#{@body}>"
    end
    # :nocov:

    class Body
      class << self
        def new(*, options)
          return options.body if options.body.is_a?(self)

          super
        end
      end

      def initialize(headers, options)
        @headers = headers
        @body = if options.body
          Transcoder.registry("body").encode(options.body)
        elsif options.form
          Transcoder.registry("form").encode(options.form)
        elsif options.json
          Transcoder.registry("json").encode(options.json)
        end
        return if @body.nil?

        @headers["content-type"] ||= @body.content_type
        @headers["content-length"] = @body.bytesize unless unbounded_body?
      end

      def each(&block)
        return enum_for(__method__) unless block_given?
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
        encoded = Transcoder.registry("chunker").encode(body) if chunked?
        encoded
      end

      def unbounded_body?
        chunked? || @body.bytesize == Float::INFINITY
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
    end

    def transition(nextstate)
      case nextstate
      when :idle
        @response = nil
        @drainer = nil
      when :headers
        return unless @state == :idle
      when :body
        return unless @state == :headers ||
                      @state == :expect

        if @headers.key?("expect")
          unless @response
            @state = :expect
            return
          end

          case @response.status
          when 100
            # deallocate
            @response = nil
          end
        end
      when :done
        return if @state == :expect
      end
      @state = nextstate
      emit(@state)
      nil
    end

    def expects?
      @headers["expect"] == "100-continue" &&
        @response && @response.status == 100
    end

    class ProcIO
      def initialize(block)
        @block = block
      end

      def write(data)
        @block.call(data)
        data.bytesize
      end
    end
  end
end
