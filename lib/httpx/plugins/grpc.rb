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

      module Message
        module_function

        def unary(response)
          verify_status(response)
          decode(response.to_s)
        end

        def stream(response); end

        def encode(bytes)
          "".b << [0, bytes.bytesize].pack("CL>") << bytes
        end

        def decode(message)
          _compressed, size = message.unpack("CL>")
          message.byteslice(5..size + 5 - 1)
        end

        def verify_status(response)
          status = Integer(response.headers["grpc-status"])
          message = response.headers["grpc-message"]

          return if status.zero?

          response.close
          raise GRPCError.new(status, message, response.trailing_metadata)
        end
      end

      class << self
        def load_dependencies(_klass)
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
        def rpc(rpc_name, input, output)
          rpc_name = rpc_name.to_s
          raise Error, "rpc #{rpc_name} already defined" if @options.grpc_rpcs.key?(rpc_name)

          # assert_can_marshal(input)
          # assert_can_marshal(output)
          with(grpc_rpcs: @options.grpc_rpcs.merge(
            rpc_name.underscore => [rpc_name, input, output]
          ).freeze)
        end

        def build_stub(origin, service = nil)
          with(origin: origin, grpc_service: service)
        end

        def execute(rpc_method, input, **opts)
          grpc_request = build_grpc_request(rpc_method, input, **opts)
          response = request(grpc_request)
          return Message.stream(response) if response.respond_to?(:each)

          Message.unary(response)
        end

        def rpc_execute(rpc_name, input, **_opts)
          rpc_name, input_enc, output_enc = @options.grpc_rpcs[rpc_name.to_s] || raise(Error, "#{rpc_name}: undefined service")
          response = execute(rpc_name, input_enc.marshal(input))

          return output_enc.stream(response) if response.respond_to?(:each)

          output_enc.unmarshal(response)
        end

        private

        def build_grpc_request(rpc_method, input, metadata: nil)
          uri = @options.origin.dup
          rpc_method = "/#{rpc_method}" unless rpc_method.start_with?("/")
          rpc_method = "/#{@options.grpc_service}#{rpc_method}" if @options.grpc_service
          uri.path = rpc_method

          headers = HEADERS
          headers = headers.merge(metadata) if metadata

          build_request(:post, uri, headers: headers, body: Message.encode(input))
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
