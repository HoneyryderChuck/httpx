# frozen_string_literal: true

require "logger"

class TestServer < WEBrick::HTTPServer
  def initialize(options = {})
    super({
      :BindAddress => "127.0.0.1",
      :Port => 0,
      :AccessLog => File.new(File::NULL),
      :Logger => Logger.new(File::NULL),
    }.merge(options))
  end

  def origin
    sock = listeners.first
    _, sock, ip, _ = sock.addr
    "http://#{ip}:#{sock}"
  end
end
