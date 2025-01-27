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

    ALLOWED_URI_SCHEMES = %w[https http].freeze

    # default value used for "user-agent" header, when not overridden.
    USER_AGENT = "httpx.rb/#{VERSION}".freeze # rubocop:disable Style/RedundantFreeze

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

    attr_reader :active_timeouts

    # will be +true+ when request body has been completely flushed.
    def_delegator :@body, :empty?

    # closes the body
    def_delegator :@body, :close

    # initializes the instance with the given +verb+ (an upppercase String, ex. 'GEt'),
    # an absolute or relative +uri+ (either as String or URI::HTTP object), the
    # request +options+ (instance of HTTPX::Options) and an optional Hash of +params+.
    #
    # Besides any of the options documented in HTTPX::Options (which would override or merge with what
    # +options+ sets), it accepts also the following:
    #
    # :params :: hash or array of key-values which will be encoded and set in the query string of request uris.
    # :body :: to be encoded in the request body payload. can be a String, an IO object (i.e. a File), or an Enumerable.
    # :form :: hash of array of key-values which will be form-urlencoded- or multipart-encoded in requests body payload.
    # :json :: hash of array of key-values which will be JSON-encoded in requests body payload.
    # :xml :: Nokogiri XML nodes which will be encoded in requests body payload.
    #
    # :body, :form, :json and :xml are all mutually exclusive, i.e. only one of them gets picked up.
    def initialize(verb, uri, options, params = EMPTY_HASH)
      @verb    = verb.to_s.upcase
      @uri     = Utils.to_uri(uri)

      @headers = options.headers.dup
      merge_headers(params.delete(:headers)) if params.key?(:headers)

      @headers["user-agent"] ||= USER_AGENT
      @headers["accept"]     ||= "*/*"

      # forego compression in the Range request case
      if @headers.key?("range")
        @headers.delete("accept-encoding")
      else
        @headers["accept-encoding"] ||= options.supported_compression_formats
      end

      @query_params = params.delete(:params) if params.key?(:params)

      @body = options.request_body_class.new(@headers, options, **params)

      @options = @body.options

      if @uri.relative? || @uri.host.nil?
        origin = @options.origin
        raise(Error, "invalid URI: #{@uri}") unless origin

        base_path = @options.base_path

        @uri = origin.merge("#{base_path}#{@uri}")
      end

      raise UnsupportedSchemeError, "#{@uri}: #{@uri.scheme}: unsupported URI scheme" unless ALLOWED_URI_SCHEMES.include?(@uri.scheme)

      @state = :idle
      @response = nil
      @peer_address = nil
      @ping = false
      @persistent = @options.persistent
      @active_timeouts = []
    end

    # whether request has been buffered with a ping
    def ping?
      @ping
    end

    # marks the request as having been buffered with a ping
    def ping!
      @ping = true
    end

    # the read timeout defined for this request.
    def read_timeout
      @options.timeout[:read_timeout]
    end

    # the write timeout defined for this request.
    def write_timeout
      @options.timeout[:write_timeout]
    end

    # the request timeout defined for this request.
    def request_timeout
      @options.timeout[:request_timeout]
    end

    def persistent?
      @persistent
    end

    # if the request contains trailer headers
    def trailers?
      defined?(@trailers)
    end

    # returns an instance of HTTPX::Headers containing the trailer headers
    def trailers
      @trailers ||= @options.headers_class.new
    end

    # returns +:r+ or +:w+, depending on whether the request is waiting for a response or flushing.
    def interests
      return :r if @state == :done || @state == :expect

      :w
    end

    def can_buffer?
      @state != :done
    end

    # merges +h+ into the instance of HTTPX::Headers of the request.
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

        # 103 Early Hints advertises resources in document to browsers.
        # not very relevant for an HTTP client, discard.
        return if response.status >= 103
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
      if (q = @query_params)
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
        @ping = false
        @response = nil
        @drainer = nil
        @active_timeouts.clear
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

    def set_timeout_callback(event, &callback)
      clb = once(event, &callback)

      # reset timeout callbacks when requests get rerouted to a different connection
      once(:idle) do
        callbacks(event).delete(clb)
      end
    end
  end
end

require_relative "request/body"
