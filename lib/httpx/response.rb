# frozen_string_literal: true

require "objspace"
require "stringio"
require "tempfile"
require "fileutils"
require "forwardable"

module HTTPX
  # Defines a HTTP response is handled internally, with a few properties exposed as attributes.
  #
  # It delegates the following methods to the corresponding HTTPX::Request:
  #
  # * HTTPX::Request#uri
  # * HTTPX::Request#peer_address
  #
  # It implements (indirectly, via the +body+) the IO write protocol to internally buffer payloads.
  #
  # It implements the IO reader protocol in order for users to buffer/stream it, acts as an enumerable
  # (of payload chunks).
  #
  class Response
    extend Forwardable
    include Callbacks

    # the HTTP response status code
    attr_reader :status

    # an HTTPX::Headers object containing the response HTTP headers.
    attr_reader :headers

    # a HTTPX::Response::Body object wrapping the response body. The following methods are delegated to it:
    #
    # * HTTPX::Response::Body#to_s
    # * HTTPX::Response::Body#to_str
    # * HTTPX::Response::Body#read
    # * HTTPX::Response::Body#copy_to
    # * HTTPX::Response::Body#close
    attr_reader  :body

    # The HTTP protocol version used to fetch the response.
    attr_reader  :version

    # returns the response body buffered in a string.
    def_delegator :@body, :to_s

    def_delegator :@body, :to_str

    # implements the IO reader +#read+ interface.
    def_delegator :@body, :read

    # copies the response body to a different location.
    def_delegator :@body, :copy_to

    # closes the body.
    def_delegator :@body, :close

    # the corresponding request uri.
    def_delegator :@request, :uri

    # the IP address of the peer server.
    def_delegator :@request, :peer_address

    # inits the instance with the corresponding +request+ to this response, an the
    # response HTTP +status+, +version+ and HTTPX::Headers instance of +headers+.
    def initialize(request, status, version, headers)
      @request = request
      @options = request.options
      @version = version
      @status = Integer(status)
      @headers = @options.headers_class.new(headers)
      @body = @options.response_body_class.new(self, @options)
      @finished = complete?
      @content_type = nil
    end

    # merges headers defined in +h+ into the response headers.
    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    # writes +data+ chunk into the response body.
    def <<(data)
      @body.write(data)
    end

    # returns the HTTPX::ContentType for the response, as per what's declared in the content-type header.
    #
    #   response.content_type #=> #<HTTPX::ContentType:xxx @header_value="text/plain">
    #   response.content_type.mime_type #=> "text/plain"
    def content_type
      @content_type ||= ContentType.new(@headers["content-type"])
    end

    # returns whether the response has been fully fetched.
    def finished?
      @finished
    end

    # marks the response as finished, freezes the headers.
    def finish!
      @finished = true
      @headers.freeze
    end

    # returns whether the response contains body payload.
    def bodyless?
      @request.verb == "HEAD" ||
        @status < 200 || # informational response
        @status == 204 ||
        @status == 205 ||
        @status == 304 || begin
          content_length = @headers["content-length"]
          return false if content_length.nil?

          content_length == "0"
        end
    end

    def complete?
      bodyless? || (@request.verb == "CONNECT" && @status == 200)
    end

    # :nocov:
    def inspect
      "#<Response:#{object_id} " \
        "HTTP/#{version} " \
        "@status=#{@status} " \
        "@headers=#{@headers} " \
        "@body=#{@body.bytesize}>"
    end
    # :nocov:

    # returns an instance of HTTPX::HTTPError if the response has a 4xx or 5xx
    # status code, or nothing.
    #
    #   ok_response.error #=> nil
    #   not_found_response.error #=> HTTPX::HTTPError instance, status 404
    def error
      return if @status < 400

      HTTPError.new(self)
    end

    # it raises the exception returned by +error+, or itself otherwise.
    #
    #   ok_response.raise_for_status #=> ok_response
    #   not_found_response.raise_for_status #=> raises HTTPX::HTTPError exception
    def raise_for_status
      return self unless (err = error)

      raise err
    end

    # decodes the response payload into a ruby object **if** the payload is valid json.
    #
    #   response.json #≈> { "foo" => "bar" } for "{\"foo\":\"bar\"}" payload
    #   response.json(symbolize_names: true) #≈> { foo: "bar" } for "{\"foo\":\"bar\"}" payload
    def json(*args)
      decode(Transcoder::JSON, *args)
    end

    # decodes the response payload into a ruby object **if** the payload is valid
    # "application/x-www-urlencoded" or "multipart/form-data".
    def form
      decode(Transcoder::Form)
    end

    private

    # decodes the response payload using the given +transcoder+, which implements the decoding logic.
    #
    # +transcoder+ must implement the internal transcoder API, i.e. respond to <tt>decode(HTTPX::Response response)</tt>,
    # which returns a decoder which responds to <tt>call(HTTPX::Response response, **kwargs)</tt>
    def decode(transcoder, *args)
      # TODO: check if content-type is a valid format, i.e. "application/json" for json parsing

      decoder = transcoder.decode(self)

      raise Error, "no decoder available for \"#{transcoder}\"" unless decoder

      @body.rewind

      decoder.call(self, *args)
    end
  end

  # Helper class which decodes the HTTP "content-type" header.
  class ContentType
    MIME_TYPE_RE = %r{^([^/]+/[^;]+)(?:$|;)}.freeze
    CHARSET_RE   = /;\s*charset=([^;]+)/i.freeze

    def initialize(header_value)
      @header_value = header_value
    end

    # returns the mime type declared in the header.
    #
    #   ContentType.new("application/json; charset=utf-8").mime_type #=> "application/json"
    def mime_type
      return @mime_type if defined?(@mime_type)

      m = @header_value.to_s[MIME_TYPE_RE, 1]
      m && @mime_type = m.strip.downcase
    end

    # returns the charset declared in the header.
    #
    #   ContentType.new("application/json; charset=utf-8").charset #=> "utf-8"
    #   ContentType.new("text/plain").charset #=> nil
    def charset
      return @charset if defined?(@charset)

      m = @header_value.to_s[CHARSET_RE, 1]
      m && @charset = m.strip.delete('"')
    end
  end

  # Wraps an error which has happened while processing an HTTP Request. It has partial
  # public API parity with HTTPX::Response, so users should rely on it to infer whether
  # the returned response is one or the other.
  #
  #   response = HTTPX.get("https://some-domain/path") #=> response is HTTPX::Response or HTTPX::ErrorResponse
  #   response.raise_for_status #=> raises if it wraps an error
  class ErrorResponse
    include Loggable
    extend Forwardable

    # the corresponding HTTPX::Request instance.
    attr_reader :request

    # the HTTPX::Response instance, when there is one (i.e. error happens fetching the response).
    attr_reader :response

    # the wrapped exception.
    attr_reader :error

    # the request uri
    def_delegator :@request, :uri

    # the IP address of the peer server.
    def_delegator :@request, :peer_address

    def initialize(request, error)
      @request = request
      @response = request.response if request.response.is_a?(Response)
      @error = error
      @options = request.options
      log_exception(@error)
    end

    # returns the exception full message.
    def to_s
      @error.full_message(highlight: false)
    end

    # closes the error resources.
    def close
      @response.close if @response && @response.respond_to?(:close)
    end

    # always true for error responses.
    def finished?
      true
    end

    # raises the wrapped exception.
    def raise_for_status
      raise @error
    end

    # buffers lost chunks to error response
    def <<(data)
      @response << data
    end
  end
end

require_relative "response/body"
require_relative "response/buffer"
require_relative "pmatch_extensions" if RUBY_VERSION >= "2.7.0"
