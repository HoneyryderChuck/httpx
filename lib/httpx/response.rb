# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Response
    extend Forwardable

    attr_reader :status, :headers, :body

    def_delegator :@body, :to_s 
    def initialize(selector, status, headers)
      @selector = selector
      @status = Integer(status)
      @headers = @options.headers_class.new(headers)
      @body = Body.new(self)
    end 

    def <<(data)
      @body << data
    end

    class Body
      MAX_THRESHOLD_SIZE = 1024 * (80 + 32) # 112 Kbytes
  
      def initialize(response, threshold_size: MAX_THRESHOLD_SIZE)
        @response = response
        @headers = response.headers
        @threshold_size = threshold_size
        @length = 0
        @buffer = nil 
        @state = :idle
      end
  
      def write(chunk)
        @length += chunk.bytesize
        transition
        @buffer.write(chunk)
        @chunk_cb[chunk] if @chunk_cb
      end
      alias :<< :write
  
      def each
        return enum_for(__method__) unless block_given?
        @chunk_cb = ->(e) { yield(e) } 
        begin
          unless @state == :idle
            rewind
            @buffer.each do |*args|
              yield(*args)
            end
          end
          buffering!
        ensure
          @chunk_cb = nil
          close
        end
      end
  
      def to_s
        buffering!
        @buffer.read
      ensure
        close
      end
  
      def empty?
        @length.zero? 
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
  
      def buffering!
        @selector.next_tick until buffered?
        rewind
      end
  
      def buffered?
        if content_length = @headers["content-length"]
          content_length = Integer(content_length)
          @length >= content_length
        elsif @headers["transfer-encoding"] == "chunked"
          # dechunk
          raise "TODO: implement de-chunking"
        else
          !@selector.running?
        end
      end
  
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
