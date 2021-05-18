# frozen_string_literal: true

begin
  require "grpc"
  require "logging"

  # A test message
  class EchoMsg
    attr_reader :msg

    def initialize(msg: "")
      @msg = msg
    end

    def self.marshal(o)
      o.msg
    end

    def self.unmarshal(msg)
      EchoMsg.new(msg: msg)
    end
  end

  # a test service that checks the cert of its peer
  class TestService
    include GRPC::GenericService
    rpc :an_rpc, EchoMsg, EchoMsg
    rpc :a_cancellable_rpc, EchoMsg, EchoMsg
    rpc :a_client_streaming_rpc, stream(EchoMsg), EchoMsg
    rpc :a_server_streaming_rpc, EchoMsg, stream(EchoMsg)
    rpc :a_bidi_rpc, stream(EchoMsg), stream(EchoMsg)

    def check_peer_cert(call)
      # error_msg = "want:\n#{client_cert}\n\ngot:\n#{call.peer_cert}"
      # fail(error_msg) unless call.peer_cert == client_cert
    end

    def an_rpc(req, call)
      check_peer_cert(call)
      req
    end

    def a_cancellable_rpc(_req, call)
      check_peer_cert(call)
      raise GRPC::Cancelled, "dump"
    end

    def a_client_streaming_rpc(call)
      check_peer_cert(call)
      call.each_remote_read.each { |r| GRPC.logger.info(r) }
      EchoMsg.new(msg: "client stream pong")
    end

    def a_server_streaming_rpc(_, call)
      check_peer_cert(call)
      call.send_initial_metadata
      [EchoMsg.new(msg: "server stream pong"), EchoMsg.new(msg: "server stream pong")]
    end

    def a_bidi_rpc(requests, call)
      check_peer_cert(call)
      requests.each { |r| GRPC.logger.info(r) }
      call.send_initial_metadata
      [EchoMsg.new(msg: "bidi pong"), EchoMsg.new(msg: "bidi pong")]
    end
  end

  # IF HTTPX_DEBUG ....
  module GRPC
    extend Logging.globally
  end
  Logging.logger.root.appenders = Logging.appenders.stdout
  Logging.logger.root.level = :info
  Logging.logger["GRPC"].level = :info
  Logging.logger["GRPC::ActiveCall"].level = :info
  Logging.logger["GRPC::BidiCall"].level = :info

  module GRPCHelpers
    include ::GRPC::Core::StatusCodes
    include ::GRPC::Core::TimeConsts
    include ::GRPC::Core::CallOps

    private

    def teardown
      super
      if @grpc_server

        @grpc_server.shutdown_and_notify(from_relative_time(2))
        @grpc_server.close
        @grpc_server_th.join if @grpc_server_th
      end

      return unless @rpc_server && !@rpc_server.stopped?

      @rpc_server.stop
      @rpc_server_th.join
    end

    def run_rpc(service, server_args: {})
      @rpc_server = ::GRPC::RpcServer.new(server_args: server_args.merge("grpc.so_reuseport" => 0))
      server_port = @rpc_server.add_http2_port("0.0.0.0:0", :this_port_is_insecure)
      @rpc_server.handle(service)

      @rpc_server_th = Thread.new { @rpc_server.run }
      @rpc_server.wait_till_running

      server_port
    end

    def run_request_response(resp, status, marshal: nil, server_args: {}, server_initial_md: {}, server_trailing_md: {})
      @grpc_server = ::GRPC::Core::Server.new(server_args.merge("grpc.so_reuseport" => 0))

      server_port = @grpc_server.add_http2_port("0.0.0.0:0", :this_port_is_insecure)

      @grpc_server_th = wakey_thread do |notifier|
        c = expect_server_to_be_invoked(notifier, metadata_to_send: server_initial_md, marshal: marshal)
        begin
          yield c
        ensure
          c.remote_send(resp)
          c.send_status(status, status == OK ? "OK" : "NOK", true, metadata: server_trailing_md)
          c.send(:set_input_stream_done)
          c.send(:set_output_stream_done)
        end
      end

      server_port
    end

    def wakey_thread(&blk)
      n = ::GRPC::Notifier.new
      t = Thread.new do
        begin
          blk.call(n)
        rescue GRPC::Core::CallError
        end
      end
      t.abort_on_exception = true
      n.wait
      t
    end

    def expect_server_to_be_invoked(notifier, metadata_to_send: nil, marshal: nil)
      @grpc_server.start
      notifier.notify(nil)
      recvd_rpc = @grpc_server.request_call
      recvd_call = recvd_rpc.call
      recvd_call.metadata = recvd_rpc.metadata
      recvd_call.run_batch(SEND_INITIAL_METADATA => metadata_to_send)
      ::GRPC::ActiveCall.new(recvd_call, marshal, marshal, INFINITE_FUTURE, metadata_received: true)
    end
  end
rescue LoadError
  module GRPCHelpers
  end
end
