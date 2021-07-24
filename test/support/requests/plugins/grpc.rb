# frozen_string_literal: true

module Requests
  module Plugins
    module GRPC
      include GRPCHelpers

      def test_plugin_grpc_unary_plain_bytestreams
        no_marshal = proc { |x| x }

        server_port = run_request_response("a_reply", OK, marshal: no_marshal) do |call|
          assert call.remote_read == "a_request"
          assert call.metadata["k1"] == "v1"
          assert call.metadata["k2"] == "v2"
        end

        grpc = grpc_plugin
        # build service
        stub = grpc.build_stub("localhost:#{server_port}")
        result = stub.execute("an_rpc_method", "a_request", metadata: { k1: "v1", k2: "v2" })

        assert result.to_s == "a_reply"
      end

      def test_plugin_grpc_call_credentials
        return unless origin.start_with?("https")

        call_credentials = -> { { "k1" => "updated-k1" } }
        no_marshal = proc { |x| x }

        server_port = run_request_response("a_reply", OK, marshal: no_marshal) do |call|
          assert call.remote_read == "a_request"
          assert call.metadata["k1"] == "updated-k1"
          assert call.metadata["k2"] == "v2"
        end

        grpc = grpc_plugin
        # build service
        stub = grpc.with_call_credentials(call_credentials).build_stub("localhost:#{server_port}")
        result = stub.execute("an_rpc_method", "a_request", metadata: { k1: "v1", k2: "v2" })

        assert result.to_s == "a_reply"
      end

      def test_plugin_grpc_compressed_request
        no_marshal = proc { |x| x }

        server_port = run_request_response("a_reply", OK, marshal: no_marshal) do |call|
          # assert call.metadata["grpc-encoding"] == "gzip", "request wasn't compressed"
          # TODO: find a way to test if request payload was indeed compressed
          assert call.remote_read == "A" * 2000
        end

        grpc = grpc_plugin
        # build service
        stub = grpc.build_stub("localhost:#{server_port}", compression: "gzip")
        result = stub.execute("an_rpc_method", "A" * 2000)

        assert result.to_s == "a_reply"
      end

      def test_plugin_grpc_compressed_response
        no_marshal = proc { |x| x }

        server_port = run_request_response("A" * 2000, OK, marshal: no_marshal,
                                                           server_initial_md: { "grpc-internal-encoding-request" => "gzip" }) do |call|
          assert call.remote_read == "a_request"
        end

        grpc = grpc_plugin
        # build service
        stub = grpc.build_stub("localhost:#{server_port}")
        result = stub.execute("an_rpc_method", "a_request")

        assert result.to_s == "A" * 2000
      end

      # Cancellation on error

      def test_plugin_grpc_deadline_exceeded
        no_marshal = proc { |x| x }

        server_port = run_request_response("a_reply", OK, marshal: no_marshal) do |call|
          sleep(3)
          assert call.remote_read == "a_request"
        end

        grpc = grpc_plugin
        # build service
        stub = grpc.build_stub("localhost:#{server_port}")

        error = assert_raises(HTTPX::GRPCError) { stub.execute("an_rpc_method", "a request", deadline: 2).to_s }
        assert error.status == ::GRPC::Core::StatusCodes::DEADLINE_EXCEEDED
      end

      def test_plugin_grpc_cancellation_on_client_error
        no_marshal = proc { |x| x }

        input = Enumerator.new do |_y|
          # y << "a_request"
          raise "oh crap"
        end

        server_port = run_request_response("a_reply", OK, marshal: no_marshal) do |call|
          # not supposed to arrive here
          begin
            call.remote_read
          rescue StandardError
            nil
          end
        end

        grpc = grpc_plugin
        # build service
        stub = grpc.build_stub("localhost:#{server_port}")

        error = assert_raises(HTTPX::Error) { stub.execute("an_rpc_method", input).to_s }
        assert error.message =~ /oh crap/
      end

      def test_plugin_grpc_cancellation_on_server_error
        server_port = run_rpc(TestService)

        grpc = grpc_plugin

        # build service
        test_service_stub = grpc.build_stub("localhost:#{server_port}", service: TestService)
        error = assert_raises(HTTPX::GRPCError) { test_service_stub.a_cancellable_rpc(EchoMsg.new(msg: "ping")).to_s }

        assert error.status == 1
        assert error.details == "dump"
      end

      def test_plugin_grpc_unary_protobuf
        server_port = run_rpc(TestService)

        grpc = grpc_plugin

        # build service
        test_service_stub = grpc.build_stub("localhost:#{server_port}", service: TestService)
        echo_response = test_service_stub.an_rpc(EchoMsg.new(msg: "ping"))

        assert echo_response.msg == "ping"
        assert echo_response.trailing_metadata["grpc-message"] == "OK"
      end

      def test_plugin_grpc_client_stream_protobuf
        server_port = run_rpc(TestService)

        grpc = grpc_plugin

        # build service
        test_service_stub = grpc.build_stub("localhost:#{server_port}", service: TestService)

        input = [EchoMsg.new(msg: "ping"), EchoMsg.new(msg: "ping")]
        response = test_service_stub.a_client_streaming_rpc(input)

        assert response.msg == "client stream pong"
        assert response.trailing_metadata["grpc-message"] == "OK"
      end

      def test_plugin_grpc_server_stream_protobuf
        server_port = run_rpc(TestService)

        grpc = grpc_plugin

        # build service
        test_service_stub = grpc.build_stub("localhost:#{server_port}", service: TestService)
        streaming_response = test_service_stub.a_server_streaming_rpc(EchoMsg.new(msg: "ping"))

        assert streaming_response.respond_to?(:each)
        assert streaming_response.trailing_metadata.nil?

        echo_responses = streaming_response.each.to_a
        assert echo_responses.map(&:msg) == ["server stream pong", "server stream pong"]
        assert streaming_response.trailing_metadata["grpc-message"] == "OK"
      end

      def test_plugin_grpc_bidi_stream_protobuf
        server_port = run_rpc(TestService)

        grpc = grpc_plugin

        # build service
        test_service_stub = grpc.build_stub("localhost:#{server_port}", service: TestService)
        input = [EchoMsg.new(msg: "ping"), EchoMsg.new(msg: "ping")]
        streaming_response = test_service_stub.a_bidi_rpc(input)

        assert streaming_response.respond_to?(:each)
        assert streaming_response.trailing_metadata.nil?

        echo_responses = streaming_response.each.to_a
        assert echo_responses.map(&:msg) == ["bidi pong", "bidi pong"]
        assert streaming_response.trailing_metadata["grpc-message"] == "OK"
      end
    end
  end
end
