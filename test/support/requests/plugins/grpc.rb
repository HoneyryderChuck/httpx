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

        # stub = ::GRPC::ClientStub.new("localhost:#{server_port}",
        #                               :this_channel_is_insecure)
        grpc = HTTPX.plugin(:grpc)
        # build service
        stub = grpc.build_stub("http://localhost:#{server_port}")
        result = stub.execute("an_rpc_method", "a_request", metadata: { k1: "v1", k2: "v2" })
        # stub = ::GRPC::ClientStub.new("localhost:#{server_port}", :this_channel_is_insecure)
        # op = stub.request_response("an_rpc_method", "a_request", no_marshal, no_marshal,
        #   return_op: true, metadata: { k1: "v1", k2: "v2" })
        # op.start_call if run_start_call_first
        # result = op.execute

        assert result == "a_reply"
      end

      def test_plugin_grpc_unary_protobuf
        server_port = run_rpc(TestService)

        grpc = HTTPX.plugin(:grpc)

        # build service
        test_service_rpcs = grpc.rpc(:an_rpc, EchoMsg, EchoMsg)
        test_service_stub = test_service_rpcs.build_stub("http://localhost:#{server_port}", TestService)
        echo_response = test_service_stub.an_rpc(EchoMsg.new(msg: "ping"))

        assert echo_response.msg == "ping"
      end
    end
  end
end
