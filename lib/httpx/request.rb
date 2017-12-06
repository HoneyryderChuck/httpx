# frozen_string_literal: true

require "http/form_data"
require "json"

module HTTPX
  class Request
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

    attr_reader :verb, :uri, :headers, :body

    def initialize(verb, uri, options)
      @verb    = verb.to_s.downcase.to_sym
      @uri     = URI(uri)
      @options = Options.new(options)

      raise(Error, "unknown method: #{verb}") unless METHODS.include?(@verb)

      @headers = Headers.new(@options.headers)
      @headers["user-agent"] ||= USER_AGENT
      @headers["accept"]     ||= "*/*" 
      
      @body = Body.new(@headers, @options) 
    end

    def scheme
      @uri.scheme
    end

    def path
      path = uri.path
      path << "/" if path.empty?
      path << "?#{uri.query}" if uri.query
      path
    end

    def <<(data)
      (@body ||= +"") << data
    end

    def authority
      host = @uri.host
      port_string = @uri.port == @uri.default_port ? nil : ":#{@uri.port}"
      "#{host}#{port_string}"
    end

    class Body
      def initialize(headers, options)
        @headers = headers
        @body = case
        when options.body
          options.body
        when options.form
          form = HTTP::FormData.create(options.form)
          @headers["content-type"] = form.content_type
          @headers["content-length"] = form.content_length
          form
        when options.json
          body = JSON.dump(options.json)
          @headers["content-type"] = "application/json; charset=#{body.encoding.name.downcase}"
          @headers["content-length"] = body.bytesize 
          body 
        end
      end

      def each(&block)
        if @body.respond_to?(:read)
          IO.copy_stream(@body, ProcIO.new(block))
        elsif @body.respond_to?(:each)
          @body.each(&block)
        else
          block[@body]
        end
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
