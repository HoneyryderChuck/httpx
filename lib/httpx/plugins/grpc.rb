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

      class << self
        def load_dependencies(*)
          require "stringio"
          require "httpx/plugins/grpc/message"
          require "httpx/plugins/grpc/call"
        end

        def configure(klass)
          klass.plugin(:persistent)
          klass.plugin(:compression)
          klass.plugin(:stream)
        end

        def extra_options(options)
          options.merge(
            fallback_protocol: "h2",
            http2_settings: { wait_for_handshake: false },
            grpc_rpcs: {}.freeze,
            grpc_compression: false,
            grpc_deadline: DEADLINE
          )
        end
      end

      module OptionsMethods
        def option_grpc_service(value)
          String(value)
        end

        def option_grpc_compression(value)
          case value
          when true, false
            value
          else
            value.to_s
          end
        end

        def option_grpc_rpcs(value)
          Hash[value]
        end

        def option_grpc_deadline(value)
          raise TypeError, ":grpc_deadline must be positive" unless value.positive?

          value
        end

        def option_call_credentials(value)
          raise TypeError, ":call_credentials must respond to #call" unless value.respond_to?(:call)

          value
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
        def with_channel_credentials(ca_path, key = nil, cert = nil, **ssl_opts)
          ssl_params = {
            **ssl_opts,
            ca_file: ca_path,
          }
          if key
            key = File.read(key) if File.file?(key)
            ssl_params[:key] = OpenSSL::PKey.read(key)
          end

          if cert
            cert = File.read(cert) if File.file?(cert)
            ssl_params[:cert] = OpenSSL::X509::Certificate.new(cert)
          end

          with(ssl: ssl_params)
        end

        def rpc(rpc_name, input, output, **opts)
          rpc_name = rpc_name.to_s
          raise Error, "rpc #{rpc_name} already defined" if @options.grpc_rpcs.key?(rpc_name)

          rpc_opts = {
            deadline: @options.grpc_deadline,
          }.merge(opts)

          session_class = Class.new(self.class) do
            class_eval(<<-OUT, __FILE__, __LINE__ + 1)
              def #{rpc_name}(input, **opts)              # def grpc_action(input, **opts)
                rpc_execute("#{rpc_name}", input, **opts) #   rpc_execute("grpc_action", input, **opts)
              end                                         # end
            OUT
          end

          session_class.new(@options.merge(
                              grpc_rpcs: @options.grpc_rpcs.merge(
                                rpc_name.underscore => [rpc_name, input, output, rpc_opts]
                              ).freeze
                            ))
        end

        def build_stub(origin, service: nil, compression: false)
          scheme = @options.ssl.empty? ? "http" : "https"

          origin = URI.parse("#{scheme}://#{origin}")

          session = self

          if service && service.respond_to?(:rpc_descs)
            # it's a grpc generic service
            service.rpc_descs.each do |rpc_name, rpc_desc|
              rpc_opts = {
                marshal_method: rpc_desc.marshal_method,
                unmarshal_method: rpc_desc.unmarshal_method,
              }

              input = rpc_desc.input
              input = input.type if input.respond_to?(:type)

              output = rpc_desc.output
              if output.respond_to?(:type)
                rpc_opts[:stream] = true
                output = output.type
              end

              session = session.rpc(rpc_name, input, output, **rpc_opts)
            end

            service = service.service_name
          end

          session.with(origin: origin, grpc_service: service, grpc_compression: compression)
        end

        def execute(rpc_method, input,
                    deadline: DEADLINE,
                    metadata: nil,
                    **opts)
          grpc_request = build_grpc_request(rpc_method, input, deadline: deadline, metadata: metadata, **opts)
          response = request(grpc_request, **opts)
          response.raise_for_status
          GRPC::Call.new(response)
        end

        private

        def rpc_execute(rpc_name, input, **opts)
          rpc_name, input_enc, output_enc, rpc_opts = @options.grpc_rpcs[rpc_name]

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
            input_enc.__send__(marshal_method, input)
          end

          call = execute(rpc_name, messages, **exec_opts)

          call.decoder = output_enc.method(unmarshal_method)

          call
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

          headers.merge!(@options.call_credentials.call) if @options.call_credentials

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
      end
    end
    register_plugin :grpc, GRPC
  end
end
