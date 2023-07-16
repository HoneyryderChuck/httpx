# frozen_string_literal: true

require "objspace"
require "stringio"
require "tempfile"
require "fileutils"
require "forwardable"

module HTTPX
  class Response
    extend Forwardable
    include Callbacks

    attr_reader :status, :headers, :body, :version

    def_delegator :@body, :to_s

    def_delegator :@body, :to_str

    def_delegator :@body, :read

    def_delegator :@body, :copy_to

    def_delegator :@body, :close

    def_delegator :@request, :uri

    def initialize(request, status, version, headers)
      @request = request
      @options = request.options
      @version = version
      @status = Integer(status)
      @headers = @options.headers_class.new(headers)
      @body = @options.response_body_class.new(self, @options)
      @finished = complete?
    end

    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    def <<(data)
      @body.write(data)
    end

    def content_type
      @content_type ||= ContentType.new(@headers["content-type"])
    end

    def finished?
      @finished
    end

    def finish!
      @finished = true
      @headers.freeze
    end

    def bodyless?
      @request.verb == "HEAD" ||
        no_data?
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

    def error
      return if @status < 400

      HTTPError.new(self)
    end

    def raise_for_status
      return self unless (err = error)

      raise err
    end

    def json(*args)
      decode(Transcoder::JSON, *args)
    end

    def form
      decode(Transcoder::Form)
    end

    def xml
      decode(Transcoder::Xml)
    end

    private

    def decode(transcoder, *args)
      # TODO: check if content-type is a valid format, i.e. "application/json" for json parsing

      decoder = transcoder.decode(self)

      raise Error, "no decoder available for \"#{transcoder}\"" unless decoder

      @body.rewind

      decoder.call(self, *args)
    end

    def no_data?
      @status < 200 || # informational response
        @status == 204 ||
        @status == 205 ||
        @status == 304 || begin
          content_length = @headers["content-length"]
          return false if content_length.nil?

          content_length == "0"
        end
    end
  end

  class ContentType
    MIME_TYPE_RE = %r{^([^/]+/[^;]+)(?:$|;)}.freeze
    CHARSET_RE   = /;\s*charset=([^;]+)/i.freeze

    def initialize(header_value)
      @header_value = header_value
    end

    def mime_type
      return @mime_type if defined?(@mime_type)

      m = @header_value.to_s[MIME_TYPE_RE, 1]
      m && @mime_type = m.strip.downcase
    end

    def charset
      return @charset if defined?(@charset)

      m = @header_value.to_s[CHARSET_RE, 1]
      m && @charset = m.strip.delete('"')
    end
  end

  class ErrorResponse
    include Loggable
    extend Forwardable

    attr_reader :request, :response, :error

    def_delegator :@request, :uri

    def initialize(request, error, options)
      @request = request
      @response = request.response if request.response.is_a?(Response)
      @error = error
      @options = Options.new(options)
      log_exception(@error)
    end

    def to_s
      @error.full_message(highlight: false)
    end

    def close
      @response.close if @response.respond_to?(:close)
    end

    def finished?
      true
    end

    def raise_for_status
      raise @error
    end
  end
end

require_relative "response/body"
require_relative "response/buffer"
require_relative "pmatch_extensions" if RUBY_VERSION >= "3.0.0"
