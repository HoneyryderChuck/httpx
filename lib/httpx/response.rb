# frozen_string_literal: true

require "objspace"
require "stringio"
require "tempfile"
require "fileutils"
require "forwardable"

module HTTPX
  class Response
    extend Forwardable

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
      @request.verb == :head ||
        no_data?
    end

    def complete?
      bodyless? || (@request.verb == :connect && @status == 200)
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
      decode("json", *args)
    end

    def form
      decode("form")
    end

    def xml
      decode("xml")
    end

    private

    def decode(format, *args)
      # TODO: check if content-type is a valid format, i.e. "application/json" for json parsing
      transcoder = Transcoder.registry(format)

      raise Error, "no decoder available for \"#{format}\"" unless transcoder.respond_to?(:decode)

      decoder = transcoder.decode(self)

      raise Error, "no decoder available for \"#{format}\"" unless decoder

      decoder.call(self, *args)
    rescue Registry::Error
      raise Error, "no decoder available for \"#{format}\""
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

    class Body
      attr_reader :encoding

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

      def filename
        return unless @headers.key?("content-disposition")

        Utils.get_filename(@headers["content-disposition"])
      end

      def to_s
        case @buffer
        when StringIO
          begin
            @buffer.string.force_encoding(@encoding)
          rescue ArgumentError
            @buffer.string
          end
        when Tempfile
          rewind
          content = _with_same_buffer_pos { @buffer.read }
          begin
            content.force_encoding(@encoding)
          rescue ArgumentError # ex: unknown encoding name - utf
            content
          end
        when nil
          "".b
        else
          @buffer
        end
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
        object_id == other.object_id || begin
          if other.respond_to?(:read)
            _with_same_buffer_pos { FileUtils.compare_stream(@buffer, other) }
          else
            to_s == other.to_s
          end
        end
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
          # @type ivar @buffer: StringIO | Tempfile
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

      def _with_same_buffer_pos
        return yield unless @buffer && @buffer.respond_to?(:pos)

        # @type ivar @buffer: StringIO | Tempfile
        current_pos = @buffer.pos
        @buffer.rewind
        begin
          yield
        ensure
          @buffer.pos = current_pos
        end
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

    attr_reader :request, :error

    def_delegator :@request, :uri

    def initialize(request, error, options)
      @request = request
      @error = error
      @options = Options.new(options)
      log_exception(@error)
    end

    def status
      warn ":#{__method__} is deprecated, use :error.message instead"
      @error.message
    end

    if Exception.method_defined?(:full_message)
      def to_s
        @error.full_message(highlight: false)
      end
    else
      def to_s
        "#{@error.message} (#{@error.class})\n" \
          "#{@error.backtrace.join("\n") if @error.backtrace}"
      end
    end

    def finished?
      true
    end

    def raise_for_status
      raise @error
    end
  end
end

require "httpx/pmatch_extensions" if RUBY_VERSION >= "3.0.0"
