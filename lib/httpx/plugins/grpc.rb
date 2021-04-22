# frozen_string_literal: true

module HTTPX
  GRPCError = Class.new(Error) do
    def initialize(status, details, metadata)
      @status = status
      @details = details
      @metadata = metadata
      super("GRPC error, code=#{status}, details=#{details}, metadata=#{metadata}")
    end
  end

  module Plugins
    #
    # This plugin makes all HTTP/1.1 requests with a body send the "Expect: 100-continue".
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Expect#expect
    #
    module GRPC
      unless String.method_defined?(:underscore)
        module StringExtensions
          refine String do
            def underscore
              s = dup # Avoid mutating the argument, as it might be frozen.
              s.gsub!(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
              s.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
              s.tr!("-", "_")
              s.downcase!
              s
            end
          end
        end
        using StringExtensions
      end

      DEADLINE = 60
      HEADERS = {
        # "accept-encoding" => "identity",
        "grpc-accept-encoding" => "identity",
        "content-type" => "application/grpc+proto",
        "grpc-timeout" => "#{DEADLINE}S",
        "te" => "trailers",
        "accept" => "application/grpc",
        # metadata fits here
        # ex "foo-bin" => base64("bar")
      }.freeze

      # Encoding module for GRPC responses
      #
      # Can encode and decode grpc messages.
      module Message
        module_function

        # decodes a unary grpc response
        def unary(response)
          verify_status(response)
          decode(response.to_s)
        end

        # lazy decodes a grpc stream response
        def stream(response)
          return enum_for(__method__, response) unless block_given?

          response.each do |frame|
            yield decode(frame)
          end
        end

        # encodes a single grpc message
        def encode(bytes)
          "".b << [0, bytes.bytesize].pack("CL>") << bytes
        end

        # decodes a single grpc message
        def decode(message)
          _compressed, size = message.unpack("CL>")
          message.byteslice(5..size + 5 - 1)
        end

        # interprets the grpc call trailing metadata, and raises an
        # exception in case of error code
        def verify_status(response)
          status = Integer(response.headers["grpc-status"])
          message = response.headers["grpc-message"]

          return if status.zero?

          response.close
          raise GRPCError.new(status, message, response.trailing_metadata)
        end
      end

      class << self
        def load_dependencies(*)
          require "google/protobuf"
        end

        def configure(klass)
          klass.plugin(:persistent)
          klass.plugin(:compression)
          klass.plugin(:stream)
        end

        def extra_options(options)
          Class.new(options.class) do
            def_option(:grpc_service, <<-OUT)
              String(value)
            OUT

            def_option(:grpc_rpcs, <<-OUT)
              Hash[value]
            OUT
          end.new(options).merge(
            fallback_protocol: "h2",
            http2_settings: { wait_for_handshake: false },
            grpc_rpcs: {}.freeze
          )
        end
      end

      module ResponseMethods
        attr_reader :trailing_metadata

        def merge_headers(trailers)
          @trailing_metadata = Hash[trailers]
          super
        end
      end

      module InstanceMethods
        def rpc(rpc_name, input, output, **opts)
          rpc_name = rpc_name.to_s
          raise Error, "rpc #{rpc_name} already defined" if @options.grpc_rpcs.key?(rpc_name)

          with(grpc_rpcs: @options.grpc_rpcs.merge(
            rpc_name.underscore => [rpc_name, input, output, opts]
          ).freeze)
        end

        def build_stub(origin, service = nil)
          with(origin: origin, grpc_service: service)
        end

        def execute(rpc_method, input, metadata: nil, **opts)
          grpc_request = build_grpc_request(rpc_method, input, metadata: metadata, **opts)
          response = request(grpc_request, **opts)
          return Message.stream(response) if response.respond_to?(:each)

          Message.unary(response)
        end

        private

        def rpc_execute(rpc_name, input, marshal_method: nil, unmarshal_method: nil, **opts)
          rpc_name, input_enc, output_enc, rpc_opts = @options.grpc_rpcs[rpc_name.to_s] || raise(Error, "#{rpc_name}: undefined service")

          marshal_method ||= rpc_opts.fetch(:marshal_method, :encode)
          unmarshal_method ||= rpc_opts.fetch(:unmarshal_method, :decode)

          messages = if input.respond_to?(:each)
            Enumerator.new do |y|
              input.each do |message|
                y << input_enc.__send__(marshal_method, message)
              end
            end
          else
            input_enc.marshal(input)
          end

          response = execute(rpc_name, messages, stream: rpc_opts.fetch(:stream, false), **opts)

          return Enumerator.new do |y|
            response.each do |message|
              y << output_enc.__send__(unmarshal_method, message)
            end
          end if response.respond_to?(:each)

          output_enc.unmarshal(response)
        end

        def build_grpc_request(rpc_method, input, metadata: nil, **)
          uri = @options.origin.dup
          rpc_method = "/#{rpc_method}" unless rpc_method.start_with?("/")
          rpc_method = "/#{@options.grpc_service}#{rpc_method}" if @options.grpc_service
          uri.path = rpc_method

          headers = HEADERS
          headers = headers.merge(metadata) if metadata

          body = if input.respond_to?(:each)
            Enumerator.new do |y|
              input.each do |message|
                y << Message.encode(message)
              end
            end
          else
            Message.encode(input)
          end
          build_request(:post, uri, headers: headers, body: body)
        end

        def respond_to_missing?(meth, *, **, &blk)
          @options.grpc_rpcs.key?(meth.to_s) || super
        end

        def method_missing(meth, *args, **kwargs, &blk)
          return rpc_execute(meth, *args, **kwargs, &blk) if @options.grpc_rpcs.key?(meth.to_s)

          super
        end
      end
    end
    register_plugin :grpc, GRPC
  end
end
