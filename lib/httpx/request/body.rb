# frozen_string_literal: true

module HTTPX
  # Implementation of the HTTP Request body as a delegator which iterates (responds to +each+) payload chunks.
  class Request::Body < SimpleDelegator
    class << self
      def new(_, options)
        return options.body if options.body.is_a?(self)

        super
      end
    end

    # inits the instance with the request +headers+ and +options+, which contain the payload definition.
    def initialize(headers, options)
      @headers = headers

      # forego compression in the Range request case
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

    # consumes and yields the request payload in chunks.
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

    # if the +@body+ is rewindable, it rewinnds it.
    def rewind
      return if empty?

      @body.rewind if @body.respond_to?(:rewind)
    end

    # return +true+ if the +body+ has been fully drained (or does nnot exist).
    def empty?
      return true if @body.nil?
      return false if chunked?

      @body.bytesize.zero?
    end

    # returns the +@body+ payload size in bytes.
    def bytesize
      return 0 if @body.nil?

      @body.bytesize
    end

    # sets the body to yield using chunked trannsfer encoding format.
    def stream(body)
      return body unless chunked?

      Transcoder::Chunker.encode(body.enum_for(:each))
    end

    # returns whether the body yields infinitely.
    def unbounded_body?
      return @unbounded_body if defined?(@unbounded_body)

      @unbounded_body = !@body.nil? && (chunked? || @body.bytesize == Float::INFINITY)
    end

    # returns whether the chunked transfer encoding header is set.
    def chunked?
      @headers["transfer-encoding"] == "chunked"
    end

    # sets the chunked transfer encoding header.
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

    # wraps the given body with the appropriate encoder.
    #
    #   ..., json: { foo: "bar" }) #=> json encoder
    #   ..., form: { foo: "bar" }) #=> form urlencoded encoder
    #   ..., form: { foo: Pathname.open("path/to/file") }) #=> multipart urlencoded encoder
    #   ..., form: { foo: File.open("path/to/file") }) #=> multipart urlencoded encoder
    #   ..., form: { body: "bla") }) #=> raw data encoder
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

      return unless @body && options.compress_request_body && @headers.key?("content-encoding")

      @headers.get("content-encoding").each do |encoding|
        @body = self.class.initialize_deflater_body(@body, encoding)
      end
    end

    class << self
      # returns the +body+ wrapped with the correct deflater accordinng to the given +encodisng+.
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

  # Wrapper yielder which can be used with functions which expect an IO writer.
  class ProcIO
    def initialize(block)
      @block = block
    end

    # Implementation the IO write protocol, which yield the given chunk to +@block+.
    def write(data)
      @block.call(data.dup)
      data.bytesize
    end
  end
end
