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
          raise GRPCError.new(status, message, response.grpc_metadata)
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
            # def_option(:grpc_services, <<-OUT)

            # OUT
          end.new(options).merge(
            fallback_protocol: "h2",
            http2_settings: { wait_for_handshake: false }
          )
        end
      end

      module ResponseMethods
        attr_reader :grpc_metadata

        def merge_headers(trailers)
          @grpc_metadata = trailers
          super
        end
      end

      module InstanceMethods
        def build_stub(origin)
          with(origin: origin)
        end

        def execute(rpc_method, req, **opts)
          grpc_request = build_grpc_request(rpc_method, req, **opts)
          response = request(grpc_request)
          return Message.stream(response) if response.respond_to?(:each)

          Message.unary(response)
        end

        private

        def build_grpc_request(rpc_method, req, metadata: nil)
          uri = @options.origin.dup
          rpc_method = "/#{rpc_method}" unless rpc_method.start_with?("/")
          uri.path = rpc_method

          headers = HEADERS
          headers = headers.merge(metadata) if metadata

          build_request(:post, uri, headers: headers, body: Message.encode(req))
        end
      end
    end
    register_plugin :grpc, GRPC
  end
end
