# frozen_string_literal: true

require "stringio"
require "tempfile"
require "fileutils"
require "forwardable"

module HTTPX
  class Response
    extend Forwardable

    attr_reader :status, :headers, :body, :version

    def_delegator :@body, :to_s

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
    end

    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    def <<(data)
      @body.write(data)
    end

    def bodyless?
      @request.verb == :head ||
        no_data?
    end

    def content_type
      ContentType.parse(@headers["content-type"])
    end

    def complete?
      bodyless? || (@request.verb == :connect && @status == 200)
    end

    # :nocov:
    def inspect
      "#<Response:#{object_id} "\
      "HTTP/#{version} " \
      "@status=#{@status} " \
      "@headers=#{@headers} " \
      "@body=#{@body.bytesize}>"
    end
    # :nocov:

    def raise_for_status
      return if @status < 400

      raise HTTPError, self
    end

    private

    def no_data?
      @status < 200 ||
        @status == 204 ||
        @status == 205 ||
        @status == 304 || begin
          content_length = @headers["content-length"]
          return false if content_length.nil?

          content_length == "0"
        end
    end

    class Body
      def initialize(response, options)
        @response = response
        @headers = response.headers
        @options = options
        @threshold_size = options.body_threshold_size
        @window_size = options.window_size
        @encoding = response.content_type.charset || Encoding::BINARY
        @length = 0
        @buffer = nil
        @state = :idle
      end

      def closed?
        @state == :closed
      end

      def write(chunk)
        return if @state == :closed

        @length += chunk.bytesize
        transition
        @buffer.write(chunk)
      end

      def read(*args)
        return unless @buffer

        rewind

        @buffer.read(*args)
      end

      def bytesize
        @length
      end

      def each
        return enum_for(__method__) unless block_given?

        begin
          if @buffer
            rewind
            while (chunk = @buffer.read(@window_size))
              yield(chunk.force_encoding(@encoding))
            end
          end
        ensure
          close
        end
      end

      def to_s
        rewind
        if @buffer
          content = @buffer.read
          begin
            return content.force_encoding(@encoding)
          rescue ArgumentError # ex: unknown encoding name - utf
            return content
          end
        end
        "".b
      ensure
        close
      end
      alias_method :to_str, :to_s

      def empty?
        @length.zero?
      end

      def copy_to(dest)
        return unless @buffer

        rewind

        if dest.respond_to?(:path) && @buffer.respond_to?(:path)
          FileUtils.mv(@buffer.path, dest.path)
        else
          ::IO.copy_stream(@buffer, dest)
        end
      end

      # closes/cleans the buffer, resets everything
      def close
        if @buffer
          @buffer.close
          @buffer.unlink if @buffer.respond_to?(:unlink)
          @buffer = nil
        end
        @length = 0
        @state = :closed
      end

      def ==(other)
        to_s == other.to_s
      end

      # :nocov:
      def inspect
        "#<HTTPX::Response::Body:#{object_id} " \
        "@state=#{@state} " \
        "@length=#{@length}>"
      end
      # :nocov:

      private

      def rewind
        return unless @buffer

        @buffer.rewind
      end

      def transition
        case @state
        when :idle
          if @length > @threshold_size
            @state = :buffer
            @buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
          else
            @state = :memory
            @buffer = StringIO.new("".b)
          end
        when :memory
          if @length > @threshold_size
            aux = @buffer
            @buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
            aux.rewind
            ::IO.copy_stream(aux, @buffer)
            # (this looks like a bug from Ruby < 2.3
            @buffer.pos = aux.pos ##################
            ########################################
            aux.close
            @state = :buffer
          end
        end

        return unless %i[memory buffer].include?(@state)
      end
    end
  end

  class ContentType
    MIME_TYPE_RE = %r{^([^/]+/[^;]+)(?:$|;)}.freeze
    CHARSET_RE   = /;\s*charset=([^;]+)/i.freeze

    attr_reader :mime_type, :charset

    def initialize(mime_type, charset)
      @mime_type = mime_type
      @charset = charset
    end

    class << self
      # Parse string and return ContentType struct
      def parse(str)
        new(mime_type(str), charset(str))
      end

      private

      def mime_type(str)
        m = str.to_s[MIME_TYPE_RE, 1]
        m && m.strip.downcase
      end

      def charset(str)
        m = str.to_s[CHARSET_RE, 1]
        m && m.strip.delete('"')
      end
    end
  end

  class ErrorResponse
    include Loggable

    attr_reader :request, :error

    def initialize(request, error, options)
      @request = request
      @error = error
      @options = Options.new(options)
      log_exception(@error)
    end

    def status
      @error.message
    end

    if Exception.method_defined?(:full_message)
      def to_s
        @error.full_message
      end
    else
      def to_s
        "#{@error.message} (#{@error.class})\n" \
        "#{@error.backtrace.join("\n") if @error.backtrace}"
      end
    end

    def raise_for_status
      raise @error
    end

    # rubocop:disable Style/MissingRespondToMissing
    def method_missing(meth, *, &block)
      raise NoMethodError, "undefined response method `#{meth}' for error response" if @options.response_class.public_method_defined?(meth)

      super
    end
    # rubocop:enable Style/MissingRespondToMissing
  end
end

require "httpx/pmatch_extensions" if RUBY_VERSION >= "3.0.0"
