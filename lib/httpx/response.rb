# frozen_string_literal: true

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

    def_delegator :@body, :read

    def_delegator :@body, :copy_to

    def_delegator :@body, :close

    def_delegator :@body, :pool=

    def_delegator :@body, :finish!

    def_delegator :@body, :finish_and_close

    def_delegator :@request, :uri

    def initialize(request, status, version, headers)
      @request = request
      @options = request.options
      @version = version
      @status = Integer(status)
      @headers = @options.headers_class.new(headers)

      @body = @options.response_body_class.new(
        self,
        threshold_size: @options.body_threshold_size,
        window_size: @options.window_size
      )
      once(:complete, &method(:finish!))
    end

    def merge_headers(h)
      @headers = @headers.merge(h)
    end

    def <<(data)
      @body.write(data)
    end

    def bodyless?
      @request.verb == :head || no_data?
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

      close
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
      attr_writer :pool

      attr_reader :bytesize

      def initialize(response, threshold_size:, window_size: 1 << 14)
        @response = response
        @headers = response.headers
        @threshold_size = threshold_size
        @window_size = window_size
        @encoding = response.content_type.charset || Encoding::BINARY
        @buffer = Buffer.new(threshold_size)
        @bytesize = 0
        @finished = false
      end

      def finish!
        @finished = true
      end

      def write(chunk)
        @bytesize += chunk.bytesize
        @buffer << chunk
      end

      # This is non-reentrant.
      def each
        return enum_for(__method__) unless block_given?

        buffer = @buffer

        # 1st step - drain the current buffer
        buffer.rewind
        buffered = buffer.read

        yield buffered.force_encoding(@encoding) unless buffered.empty?

        # 2. yield chunks as they come
        begin
          loop do
            break if finished?

            @buffer = "".b

            @pool.next_tick

            yield(@buffer.force_encoding(@encoding)) unless @buffer.empty?
          end
        ensure
          @buffer = buffer
          close
        end
      end

      def to_s
        # early exit if the operation has been done already
        return @content if defined?(@content)

        buffer = @buffer
        begin
          @buffer.rewind
          # drain buffer to memory
          @content = read

          @buffer = @content
          @pool.next_tick until finished?

          @content.force_encoding(@encoding)
        ensure
          @buffer = buffer
          close
        end
      end
      alias_method :to_str, :to_s

      # this will read from the buffer directly
      def read(*args)
        @buffer.rewind
        @buffer.read(*args)
      end

      def copy_to(dest)
        if @content
          buffer = StringIO.new(@content)
          ::IO.copy_stream(buffer, dest)
        else
          @pool.next_tick until finished?
          @buffer.copy_to(dest)
        end
      end

      def finish_and_close
        @pool.next_tick until finished?
        close
      end

      # closes/cleans the buffer, resets everything
      def close
        @buffer.close
      end

      def ==(other)
        to_s == other.to_s
      end

      # :nocov:
      def inspect
        "#<HTTPX::Response::Body:#{object_id} " \
        "@state=#{@state} " \
        "@bytesize=#{@bytesize}>"
      end
      # :nocov:

      private

      def finished?
        @finished
      end

      class Buffer
        def initialize(threshold)
          @threshold = threshold
          @buffer = nil
          @size = 0
          @closed = false
        end

        def <<(chunk)
          return if @closed

          @size += chunk.bytesize

          if @size > @threshold
            buffer = @buffer
            @buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
            if buffer
              buffer.rewind
              ::IO.copy_stream(buffer, @buffer)
              # (this looks like a bug from Ruby < 2.3
              @buffer.pos = buffer.pos ###############
              ########################################
            end
          else
            @buffer ||= StringIO.new("".b, File::RDWR)
          end

          @buffer << chunk
        end

        def read(*args)
          raise Error, "response is closed" if @closed
          return "".b unless @buffer

          @buffer.read(*args)
        end

        def rewind
          raise Error, "response is closed" if @closed

          @buffer.rewind if @buffer
        end

        def copy_to(dest)
          raise Error, "response is closed" if @closed
          return unless @buffer

          @buffer.rewind
          if dest.respond_to?(:path) && @buffer.respond_to?(:path)
            FileUtils.mv(@buffer.path, dest.path)
          else
            ::IO.copy_stream(@buffer, dest)
          end
        end

        # closes/cleans the buffer, resets everything
        def close
          @buffer.close if @buffer.respond_to?(:close)
          @buffer.unlink if @buffer.respond_to?(:unlink)
          @buffer = nil
          @closed = true
        end
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

    def to_s
      @error.backtrace.join("\n")
    end

    def raise_for_status
      raise @error
    end

    # rubocop:disable Style/MissingRespondToMissing
    def method_missing(meth, *, &block)
      raise NoMethodError, "undefined response method `#{meth}' for error response" if Response.public_method_defined?(meth)

      super
    end
    # rubocop:enable Style/MissingRespondToMissing
  end
end
