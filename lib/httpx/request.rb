# frozen_string_literal: true

require "delegate"
require "forwardable"

module HTTPX
  # Defines how an HTTP request is handled internally, both in terms of making attributes accessible,
  # as well as maintaining the state machine which manages streaming the request onto the wire.
  class Request
    extend Forwardable
    include Callbacks
    using URIExtensions

    # default value used for "user-agent" header, when not overridden.
    USER_AGENT = "httpx.rb/#{VERSION}"

    # the upcased string HTTP verb for this request.
    attr_reader :verb

    # the absolute URI object for this request.
    attr_reader :uri

    # an HTTPX::Headers object containing the request HTTP headers.
    attr_reader :headers

    # an HTTPX::Request::Body object containing the request body payload (or +nil+, whenn there is none).
    attr_reader :body

    # a symbol describing which frame is currently being flushed.
    attr_reader :state

    # an HTTPX::Options object containing request options.
    attr_reader :options

    # the corresponding HTTPX::Response object, when there is one.
    attr_reader :response

    # Exception raised during enumerable body writes.
    attr_reader :drain_error

    # The IP address from the peer server.
    attr_accessor :peer_address

    attr_writer :persistent

    # will be +true+ when request body has been completely flushed.
    def_delegator :@body, :empty?

    # initializes the instance with the given +verb+, an absolute or relative +uri+, and the
    # request options.
    def initialize(verb, uri, options = {})
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
      @response = nil
      @peer_address = nil
      @persistent = @options.persistent
    end

    # the read timeout defied for this requet.
    def read_timeout
      @options.timeout[:read_timeout]
    end

    # the write timeout defied for this requet.
    def write_timeout
      @options.timeout[:write_timeout]
    end

    # the request timeout defied for this requet.
    def request_timeout
      @options.timeout[:request_timeout]
    end

    def persistent?
      @persistent
    end

    def trailers?
      defined?(@trailers)
    end

    def trailers
      @trailers ||= @options.headers_class.new
    end

    # returns +:r+ or +:w+, depending on whether the request is waiting for a response or flushing.
    def interests
      return :r if @state == :done || @state == :expect

      :w
    end

    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    # the URI scheme of the request +uri+.
    def scheme
      @uri.scheme
    end

    # sets the +response+ on this request.
    def response=(response)
      return unless response

      if response.is_a?(Response) && response.status < 200
        # deal with informational responses

        if response.status == 100 && @headers.key?("expect")
          @informational_status = response.status
          return
        end

        if response.status >= 103
          # 103 Early Hints advertises resources in document to browsers.
          # not very relevant for an HTTP client, discard.
          return
        end
      end

      @response = response

      emit(:response_started, response)
    end

    # returnns the URI path of the request +uri+.
    def path
      path = uri.path.dup
      path =  +"" if path.nil?
      path << "/" if path.empty?
      path << "?#{query}" unless query.empty?
      path
    end

    # returs the URI authority of the request.
    #
    #   session.build_request("GET", "https://google.com/query").authority #=> "google.com"
    #   session.build_request("GET", "http://internal:3182/a").authority #=> "internal:3182"
    def authority
      @uri.authority
    end

    # returs the URI origin of the request.
    #
    #   session.build_request("GET", "https://google.com/query").authority #=> "https://google.com"
    #   session.build_request("GET", "http://internal:3182/a").authority #=> "http://internal:3182"
    def origin
      @uri.origin
    end

    # returs the URI query string of the request (when available).
    #
    #   session.build_request("GET", "https://search.com").query #=> ""
    #   session.build_request("GET", "https://search.com?q=a").query #=> "q=a"
    #   session.build_request("GET", "https://search.com", params: { q: "a"}).query #=> "q=a"
    #   session.build_request("GET", "https://search.com?q=a", params: { foo: "bar"}).query #=> "q=a&foo&bar"
    def query
      return @query if defined?(@query)

      query = []
      if (q = @options.params)
        query << Transcoder::Form.encode(q)
      end
      query << @uri.query if @uri.query
      @query = query.join("&")
    end

    # consumes and returns the next available chunk of request body that can be sent
    def drain_body
      return nil if @body.nil?

      @drainer ||= @body.each
      chunk = @drainer.next.dup

      emit(:body_chunk, chunk)
      chunk
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

    # moves on to the +nextstate+ of the request state machine (when all preconditions are met)
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

    # whether the request supports the 100-continue handshake and already processed the 100 response.
    def expects?
      @headers["expect"] == "100-continue" && @informational_status == 100 && !@response
    end
  end
end

require_relative "request/body"
