# frozen_string_literal: true

module HTTPX
  # Implementation of the HTTP Request body as a delegator which iterates (responds to +each+) payload chunks.
  class Request::Body < SimpleDelegator
    class << self
      def new(_, options, body: nil, **params)
        if body.is_a?(self)
          # request derives its options from body
          body.options = options.merge(params)
          return body
        end

        super
      end
    end

    attr_accessor :options

    # inits the instance with the request +headers+, +options+ and +params+, which contain the payload definition.
    # it wraps the given body with the appropriate encoder on initialization.
    #
    #   ..., json: { foo: "bar" }) #=> json encoder
    #   ..., form: { foo: "bar" }) #=> form urlencoded encoder
    #   ..., form: { foo: Pathname.open("path/to/file") }) #=> multipart urlencoded encoder
    #   ..., form: { foo: File.open("path/to/file") }) #=> multipart urlencoded encoder
    #   ..., form: { body: "bla") }) #=> raw data encoder
    def initialize(headers, options, body: nil, form: nil, json: nil, xml: nil, **params)
      @headers = headers
      @options = options.merge(params)

      @body = if body
        Transcoder::Body.encode(body)
      elsif form
        Transcoder::Form.encode(form)
      elsif json
        Transcoder::JSON.encode(json)
      elsif xml
        Transcoder::Xml.encode(xml)
      end

      if @body
        if @options.compress_request_body && @headers.key?("content-encoding")

          @headers.get("content-encoding").each do |encoding|
            @body = self.class.initialize_deflater_body(@body, encoding)
          end
        end

        @headers["content-type"] ||= @body.content_type
        @headers["content-length"] = @body.bytesize unless unbounded_body?
      end

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
