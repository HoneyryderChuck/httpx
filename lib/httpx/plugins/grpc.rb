# frozen_string_literal: true

module HTTPX
  GRPCError = Class.new(Error) do
    attr_reader :status, :details, :metadata

    def initialize(status, details, metadata)
      @status = status
      @details = details
      @metadata = metadata
      super("GRPC error, code=#{status}, details=#{details}, metadata=#{metadata}")
    end
  end

  module Plugins
    #
    # This plugin adds DSL to build GRPC interfaces.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/GRPC
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
      MARSHAL_METHOD = :encode
      UNMARSHAL_METHOD = :decode
      HEADERS = {
        "content-type" => "application/grpc",
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
          decode(response.to_s, encodings: response.headers.get("grpc-encoding"), encoders: response.encoders)
        end

        # lazy decodes a grpc stream response
        def stream(response)
          return enum_for(__method__, response) unless block_given?

          response.each do |frame|
            yield decode(frame, encodings: response.headers.get("grpc-encoding"), encoders: response.encoders)
          end

          verify_status(response)
        end

        # encodes a single grpc message
        def encode(bytes, deflater:)
          if deflater
            compressed_flag = 1
            bytes = deflater.deflate(StringIO.new(bytes))
          else
            compressed_flag = 0
          end

          "".b << [compressed_flag, bytes.bytesize].pack("CL>") << bytes.to_s
        end

        # decodes a single grpc message
        def decode(message, encodings:, encoders:)
          compressed, size = message.unpack("CL>")
          data = message.byteslice(5..size + 5 - 1)
          if compressed == 1
            encodings.reverse_each do |algo|
              inflater = encoders.registry(algo).inflater(size)
              data = inflater.inflate(data)
              size = data.bytesize
            end
          end
          data
        end

        def cancel(request)
          request.emit(:refuse, :client_cancellation)
        end

        # interprets the grpc call trailing metadata, and raises an
        # exception in case of error code
        def verify_status(response)
          # return standard errors if need be
          response.raise_for_status

          status = Integer(response.headers["grpc-status"])
          message = response.headers["grpc-message"]

          return if status.zero?

          response.close
          raise GRPCError.new(status, message, response.trailing_metadata)
        end
      end

      class << self
        def load_dependencies(*)
          require "stringio"
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

            def_option(:grpc_compression, <<-OUT)
              case value
              when true, false
                value
              else
                value.to_s
              end
            OUT

            def_option(:grpc_rpcs, <<-OUT)
              Hash[value]
            OUT

            def_option(:grpc_deadline, <<-OUT)
              raise Error, ":grpc_deadline must be positive" unless value.positive?

              value
            OUT
          end.new(options).merge(
            fallback_protocol: "h2",
            http2_settings: { wait_for_handshake: false },
            grpc_rpcs: {}.freeze,
            grpc_compression: false,
            grpc_deadline: DEADLINE
          )
        end
      end

      module ResponseMethods
        attr_reader :trailing_metadata

        def merge_headers(trailers)
          @trailing_metadata = Hash[trailers]
          super
        end

        def encoders
          @options.encodings
        end
      end

      module InstanceMethods
        def rpc(rpc_name, input, output, **opts)
          rpc_name = rpc_name.to_s
          raise Error, "rpc #{rpc_name} already defined" if @options.grpc_rpcs.key?(rpc_name)

          rpc_opts = {
            deadline: @options.grpc_deadline,
          }.merge(opts)

          with(grpc_rpcs: @options.grpc_rpcs.merge(
            rpc_name.underscore => [rpc_name, input, output, rpc_opts]
          ).freeze)
        end

        def build_stub(origin, service: nil, compression: false)
          with(origin: origin, grpc_service: service, grpc_compression: compression)
        end

        def execute(rpc_method, input,
                    deadline: DEADLINE,
                    metadata: nil,
                    **opts)
          grpc_request = build_grpc_request(rpc_method, input, deadline: deadline, metadata: metadata, **opts)
          response = request(grpc_request, **opts)
          return Message.stream(response) if response.respond_to?(:each)

          Message.unary(response)
        end

        private

        def rpc_execute(rpc_name, input, **opts)
          rpc_name, input_enc, output_enc, rpc_opts = @options.grpc_rpcs[rpc_name.to_s] || raise(Error, "#{rpc_name}: undefined service")

          exec_opts = rpc_opts.merge(opts)

          marshal_method ||= exec_opts.delete(:marshal_method) || MARSHAL_METHOD
          unmarshal_method ||= exec_opts.delete(:unmarshal_method) || UNMARSHAL_METHOD

          messages = if input.respond_to?(:each)
            Enumerator.new do |y|
              input.each do |message|
                y << input_enc.__send__(marshal_method, message)
              end
            end
          else
            input_enc.marshal(input)
          end

          response = execute(rpc_name, messages, **exec_opts)

          return Enumerator.new do |y|
            response.each do |message|
              y << output_enc.__send__(unmarshal_method, message)
            end
          end if response.respond_to?(:each)

          output_enc.unmarshal(response)
        end

        def build_grpc_request(rpc_method, input, deadline:, metadata: nil, **)
          uri = @options.origin.dup
          rpc_method = "/#{rpc_method}" unless rpc_method.start_with?("/")
          rpc_method = "/#{@options.grpc_service}#{rpc_method}" if @options.grpc_service
          uri.path = rpc_method

          headers = HEADERS.merge(
            "grpc-accept-encoding" => ["identity", *@options.encodings.registry.keys]
          )
          unless deadline == Float::INFINITY
            # convert to milliseconds
            deadline = (deadline * 1000.0).to_i
            headers["grpc-timeout"] = "#{deadline}m"
          end

          headers = headers.merge(metadata) if metadata

          # prepare compressor
          deflater = nil
          compression = @options.grpc_compression == true ? "gzip" : @options.grpc_compression

          if compression
            headers["grpc-encoding"] = compression
            deflater = @options.encodings.registry(compression).deflater
          end

          body = if input.respond_to?(:each)
            Enumerator.new do |y|
              input.each do |message|
                y << Message.encode(message, deflater: deflater)
              end
            end
          else
            Message.encode(input, deflater: deflater)
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
