# frozen_string_literal: true

require_relative "test"

class ResetConnectionServer < TestServer
  attr_reader :requests

  def initialize(resets:, **options)
    super(options)
    @resets = resets
    @requests = Queue.new

    mount_proc("/") do |_req, res|
      res.body = "cached response"
      res["Cache-Control"] = "max-age=3600"
    end
  end

  def run(sock)
    @requests << true

    if @requests.size <= @resets
      while (line = sock.gets)
        break if line == "\r\n"
      end
      sock.to_io.setsockopt(Socket::SOL_SOCKET, Socket::SO_LINGER, [1, 0].pack("ii"))
      return
    end

    super
  end
end
