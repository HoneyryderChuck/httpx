# frozen_string_literal: true

module HTTPX
  class StreamResponse
    attr_reader :request

    def initialize(request, session)
      @request = request
      @options = @request.options
      @session = session
      @response_enum = nil
      @buffered_chunks = []
    end

    def each(&block)
      return enum_for(__method__) unless block

      if (response_enum = @response_enum)
        @response_enum = nil
        # streaming already started, let's finish it

        while (chunk = @buffered_chunks.shift)
          block.call(chunk)
        end

        # consume enum til the end
        begin
          while (chunk = response_enum.next)
            block.call(chunk)
          end
        rescue StopIteration
          return
        end
      end

      @request.stream = self

      begin
        @on_chunk = block

        response = @session.request(@request)

        response.raise_for_status
      ensure
        @on_chunk = nil
      end
    end

    def each_line
      return enum_for(__method__) unless block_given?

      line = "".b

      each do |chunk|
        line << chunk

        while (idx = line.index("\n"))
          yield line.byteslice(0..(idx - 1))

          line = line.byteslice((idx + 1)..-1)
        end
      end

      yield line unless line.empty?
    end

    # This is a ghost method. It's to be used ONLY internally, when processing streams
    def on_chunk(chunk)
      raise NoMethodError unless @on_chunk

      @on_chunk.call(chunk)
    end

    # :nocov:
    def inspect
      "#<#{self.class}:#{object_id}>"
    end
    # :nocov:

    def to_s
      if @request.response
        @request.response.to_s
      else
        @buffered_chunks.join
      end
    end

    private

    def response
      @request.response || begin
        response_enum = each
        while (chunk = response_enum.next)
          @buffered_chunks << chunk
          break if @request.response
        end
        @response_enum = response_enum
        @request.response
      end
    end

    def respond_to_missing?(meth, include_private)
      if (response = @request.response)
        response.respond_to_missing?(meth, include_private)
      else
        @options.response_class.method_defined?(meth) || (include_private && @options.response_class.private_method_defined?(meth))
      end || super
    end

    def method_missing(meth, *args, **kwargs, &block)
      return super unless response.respond_to?(meth)

      response.__send__(meth, *args, **kwargs, &block)
    end
  end

  module Plugins
    #
    # This plugin adds support for streaming a response (useful for i.e. "text/event-stream" payloads).
    #
    # https://gitlab.com/os85/httpx/wikis/Stream
    #
    module Stream
      STREAM_REQUEST_OPTIONS = { timeout: { read_timeout: Float::INFINITY, operation_timeout: 60 }.freeze }.freeze

      def self.extra_options(options)
        options.merge(
          stream: false,
          timeout: { read_timeout: Float::INFINITY, operation_timeout: 60 },
          stream_response_class: Class.new(StreamResponse, &Options::SET_TEMPORARY_NAME).freeze
        )
      end

      # adds support for the following options:
      #
      # :stream :: whether the request to process should be handled as a stream (defaults to <tt>false</tt>).
      # :stream_response_class :: Class used to build the stream response object.
      module OptionsMethods
        def option_stream(val)
          val
        end

        def option_stream_response_class(value)
          value
        end

        def extend_with_plugin_classes(pl)
          return super unless defined?(pl::StreamResponseMethods)

          @stream_response_class = @stream_response_class.dup
          Options::SET_TEMPORARY_NAME[@stream_response_class, pl]
          @stream_response_class.__send__(:include, pl::StreamResponseMethods) if defined?(pl::StreamResponseMethods)

          super
        end
      end

      module InstanceMethods
        def request(*args, **options)
          if args.first.is_a?(Request)
            requests = args

            request = requests.first

            unless request.options.stream && !request.stream
              if options[:stream]
                warn "passing `stream: true` with a request object is not supported anymore. " \
                     "You can instead build the request object with `stream :true`"
              end
              return super
            end
          else
            return super unless options[:stream]

            requests = build_requests(*args, options)

            request = requests.first
          end

          raise Error, "only 1 response at a time is supported for streaming requests" unless requests.size == 1

          @options.stream_response_class.new(request, self)
        end

        def build_request(verb, uri, params = EMPTY_HASH, options = @options)
          return super unless params[:stream]

          super(verb, uri, params, options.merge(STREAM_REQUEST_OPTIONS.merge(stream: true)))
        end
      end

      module RequestMethods
        attr_accessor :stream
      end

      module ResponseMethods
        def stream
          request = @request.root_request if @request.respond_to?(:root_request)
          request ||= @request

          request.stream
        end
      end

      module ResponseBodyMethods
        def initialize(*)
          super
          @stream = @response.stream
        end

        def write(chunk)
          return super unless @stream

          return 0 if chunk.empty?

          chunk = decode_chunk(chunk)

          @stream.on_chunk(chunk.dup)

          chunk.bytesize
        end

        private

        def transition(*)
          return if @stream

          super
        end
      end
    end
    register_plugin :stream, Stream
  end
end
