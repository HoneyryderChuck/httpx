# frozen_string_literal: true

begin
  require "grpc"
  require "logging"

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
      return unless @grpc_server

      @grpc_server.shutdown_and_notify(from_relative_time(2))
      @grpc_server.close
      @grpc_server_th.join if @grpc_server_th
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
        blk.call(n)
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
