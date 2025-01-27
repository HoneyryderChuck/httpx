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
          yield line.byteslice(0..idx - 1)

          line = line.byteslice(idx + 1..-1)
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
      "#<StreamResponse:#{object_id}>"
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
      def self.extra_options(options)
        options.merge(timeout: { read_timeout: Float::INFINITY, operation_timeout: 60 })
      end

      module InstanceMethods
        def request(*args, stream: false, **options)
          return super(*args, **options) unless stream

          requests = args.first.is_a?(Request) ? args : build_requests(*args, options)
          raise Error, "only 1 response at a time is supported for streaming requests" unless requests.size == 1

          request = requests.first

          StreamResponse.new(request, self)
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

          chunk.size
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
