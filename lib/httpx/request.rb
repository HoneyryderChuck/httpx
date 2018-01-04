# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Request
    extend Forwardable

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

    attr_accessor :response

    def_delegator :@body, :<<
    
    def_delegator :@body, :empty?

    def initialize(verb, uri, options = {})
      @verb    = verb.to_s.downcase.to_sym
      @uri     = URI(uri)
      @options = Options.new(options)

      raise(Error, "unknown method: #{verb}") unless METHODS.include?(@verb)

      @headers = @options.headers_class.new(@options.headers)
      @headers["user-agent"] ||= USER_AGENT
      @headers["accept"]     ||= "*/*" 
      
      @body = Body.new(@headers, @options)
      @state = :idle
    end

    def scheme
      @uri.scheme
    end

    def path
      path = uri.path
      path << "/" if path.empty?
      path << "?#{query}" unless query.empty?
      path
    end

    def authority
      host = @uri.host
      port_string = @uri.port == @uri.default_port ? nil : ":#{@uri.port}"
      "#{host}#{port_string}"
    end

    def query
      return @query if defined?(@query)
      query = []
      if q = @options.params
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

    class Body
      class << self
        def new(*, options)
          return options.body if options.body.is_a?(self)
          super
        end
      end

      def initialize(headers, options)
        @headers = headers
        @body = case
        when options.body
          Transcoder.registry("body").encode(options.body)
        when options.form
          Transcoder.registry("form").encode(options.form)
        when options.json
          Transcoder.registry("json").encode(options.json)
        end
        return if @body.nil?
        @headers.get("content-encoding").each do |encoding|
          @body = Transcoder.registry(encoding).encode(@body)
        end
        @headers["content-type"] ||= @body.content_type
        @headers["content-length"] ||= @body.bytesize unless chunked?
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
        bytesize.zero?
      end

      def bytesize
        return 0 if @body.nil?
        if @body.respond_to?(:bytesize)
          @body.bytesize
        elsif @body.respond_to?(:size)
          @body.size
        else
          raise Error, "cannot determine size of body: #{@body.inspect}"
        end
      end

      def stream(body)
        encoded = body
        if chunked?
          encoded = Transcoder.registry("chunker").encode(body) 
        end
        encoded
      end

      def chunked?
        @headers["transfer-encoding"] == "chunked"
      end
    end

    def transition(nextstate)
      case nextstate
      when :idle

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
          when 417
            @response = ErrorResponse.new("Expectation Failed", 0)
            return
          end
        end
      when :done
        return unless @state == :body ||
                      @state == :headers
      end
      @state = nextstate
      nil
    end

    def expects?
      @headers["expect"] == "100-continue" &&
      @response && @response.status == 100
    end

    private

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
