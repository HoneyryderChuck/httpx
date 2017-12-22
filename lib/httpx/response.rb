# frozen_string_literal: true

require "stringio"
require "tempfile"
require "fileutils"
require "forwardable"

module HTTPX
  class Response
    extend Forwardable

    attr_reader :status, :headers, :body

    def_delegator :@body, :to_s 
    
    def_delegator :@body, :read
    
    def_delegator :@body, :copy_to
    
    def_delegator :@body, :close

    def initialize(request, status, headers, options = {})
      @options = Options.new(options) 
      @request = request
      @status = Integer(status)
      @headers = @options.headers_class.new(headers)
      @body = @options.response_body_class.new(self, threshold_size: @options.body_threshold_size,
                                                     window_size: @options.window_size)
    end 

    def <<(data)
      @body.write(data)
    end

    def bodyless?
      @request.verb == :head ||
      @status < 200 ||
      @status == 201 ||
      @status == 204 ||
      @status == 205 ||
      @status == 304
    end

    def content_type
      ContentType.parse(@headers["content-type"])
    end

    class Body
      def initialize(response, threshold_size: , window_size: 1 << 14)
        @response = response
        @headers = response.headers
        @threshold_size = threshold_size
        @window_size = window_size 
        @encoding = response.content_type.charset || Encoding::BINARY
        @length = 0
        @buffer = nil 
        @state = :idle
      end
  
      def write(chunk)
        @length += chunk.bytesize
        transition
        @buffer.write(chunk)
      end

      def read(*args)
        return unless @buffer
        @buffer.read(*args)
      end

      def bytesize
        @length
      end

      def each
        return enum_for(__method__) unless block_given?
        begin
          unless @state == :idle
            rewind
            while chunk = @buffer.read(@window_size)
              yield(chunk)
            end
          end
        ensure
          close
        end
      end
 
      def to_s
        rewind
        return @buffer.read if @buffer
        ""
      ensure
        close
      end
  
      def empty?
        @length.zero? 
      end
 
      def copy_to(dest)
        return unless @buffer
        if dest.is_a?(File) and @buffer.is_a?(File)
          FileUtils.mv(@buffer.path, dest.path)
        else
          @buffer.rewind
          ::IO.copy_stream(@buffer, dest)
        end
      end

      # closes/cleans the buffer, resets everything
      def close
        return if @state == :idle
        @buffer.close
        @buffer.unlink if @buffer.respond_to?(:unlink)
        @buffer = nil
        @length = 0
        @state = :idle
      end
  
      def ==(other)
        to_s == other.to_s
      end
  
      private
 
      def rewind
        return if @state == :idle
        @buffer.rewind
      end
  
      # def buffered?
      #   return true if @response.bodyless?
      #   if content_length = @headers["content-length"]
      #     content_length = Integer(content_length)
      #     @length >= content_length
      #   elsif @headers["transfer-encoding"] == "chunked"
      #     # dechunk
      #     raise "TODO: implement de-chunking"
      #   else
      #     true
      #   end
      # end
  
      def transition
        case @state
        when :idle
          if @length > @threshold_size
            @state = :buffer
            @buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
          else
            @state = :memory
            @buffer = StringIO.new("".b, File::RDWR)
          end
        when :memory
          if @length > @threshold_size
            aux = @buffer
            @buffer = Tempfile.new("palanca", encoding: Encoding::BINARY, mode: File::RDWR)
            aux.rewind
            IO.copy_stream(aux, @buffer)
            # TODO: remove this if/when minor ruby is 2.3
            # (this looks like a bug from older versions)
            @buffer.pos = aux.pos #######################
            #############################################
            aux.close
            @state = :buffer
          end
        end
  
        return unless %i[memory buffer].include?(@state)
      end
    end
  end

  class ContentType
    MIME_TYPE_RE = %r{^([^/]+/[^;]+)(?:$|;)}
    CHARSET_RE   = /;\s*charset=([^;]+)/i

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

      # :nodoc:
      def mime_type(str)
        m = str.to_s[MIME_TYPE_RE, 1]
        m && m.strip.downcase
      end

      # :nodoc:
      def charset(str)
        m = str.to_s[CHARSET_RE, 1]
        m && m.strip.delete('"')
      end
    end
  end

  class ErrorResponse

    attr_reader :error, :retries

    alias :status :error

    def initialize(error, retries)
      @error = error
      @retries = retries
    end

    def retryable?
      @retries.positive?
    end
  end

end
