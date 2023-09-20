# frozen_string_literal: true

module HTTPX
  class Request::Body < SimpleDelegator
    class << self
      def new(_, options)
        return options.body if options.body.is_a?(self)

        super
      end
    end

    attr_reader :threshold_size

    def initialize(headers, options)
      @headers = headers
      @threshold_size = options.body_threshold_size

      # forego compression in the Range cases
      if @headers.key?("range")
        @headers.delete("accept-encoding")
      else
        @headers["accept-encoding"] ||= options.supported_compression_formats
      end

      initialize_body(options)

      return if @body.nil?

      @headers["content-type"] ||= @body.content_type
      @headers["content-length"] = @body.bytesize unless unbounded_body?
      super(@body)
    end

    def each(&block)
      return enum_for(__method__) unless block
      return if @body.nil?

      body = stream(@body)
      if body.respond_to?(:read)
        ::IO.copy_stream(body, ProcIO.new(block))
      elsif body.respond_to?(:each)
        body.each(&block)
      else
        block[body.to_s]
      end
    end

    def rewind
      return if empty?

      @body.rewind if @body.respond_to?(:rewind)
    end

    def empty?
      return true if @body.nil?
      return false if chunked?

      @body.bytesize.zero?
    end

    def bytesize
      return 0 if @body.nil?

      @body.bytesize
    end

    def stream(body)
      encoded = body
      encoded = Transcoder::Chunker.encode(body.enum_for(:each)) if chunked?
      encoded
    end

    def unbounded_body?
      return @unbounded_body if defined?(@unbounded_body)

      @unbounded_body = !@body.nil? && (chunked? || @body.bytesize == Float::INFINITY)
    end

    def chunked?
      @headers["transfer-encoding"] == "chunked"
    end

    def chunk!
      @headers.add("transfer-encoding", "chunked")
    end

    # :nocov:
    def inspect
      "#<HTTPX::Request::Body:#{object_id} " \
        "#{unbounded_body? ? "stream" : "@bytesize=#{bytesize}"}>"
    end
    # :nocov:

    private

    def initialize_body(options)
      @body = if options.body
        Transcoder::Body.encode(options.body)
      elsif options.form
        Transcoder::Form.encode(options.form)
      elsif options.json
        Transcoder::JSON.encode(options.json)
      elsif options.xml
        Transcoder::Xml.encode(options.xml)
      end

      return unless @body

      return unless options.compress_request_body

      return unless @headers.key?("content-encoding")

      @headers.get("content-encoding").each do |encoding|
        @body = self.class.initialize_deflater_body(@body, encoding)
      end
    end

    class << self
      def initialize_deflater_body(body, encoding)
        case encoding
        when "gzip"
          Transcoder::GZIP.encode(body)
        when "deflate"
          Transcoder::Deflate.encode(body)
        when "identity"
          body
        else
          body
        end
      end
    end
  end

  class ProcIO
    def initialize(block)
      @block = block
    end

    def write(data)
      @block.call(data.dup)
      data.bytesize
    end
  end
end
