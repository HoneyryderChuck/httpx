# frozen_string_literal: true

module HTTPX
  class StreamResponse
    def initialize(request, session)
      @request = request
      @session = session
      @response = nil
    end

    def each(&block)
      return enum_for(__method__) unless block

      @request.stream = self

      begin
        @on_chunk = block

        if @request.response
          # if we've already started collecting the payload, yield it first
          # before proceeding.
          body = @request.response.body

          body.each do |chunk|
            on_chunk(chunk)
          end
        end

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
      response.to_s
    end

    private

    def response
      return @response if @response

      @request.response || begin
        @response = @session.request(@request)
      end
    end

    def respond_to_missing?(meth, *args)
      response.respond_to?(meth, *args) || super
    end

    def method_missing(meth, *args, &block)
      return super unless response.respond_to?(meth)

      response.__send__(meth, *args, &block)
    end
  end

  module Plugins
    #
    # This plugin adds support for stream response (text/event-stream).
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
