# frozen_string_literal: true

require "webrick"
require "logger"

class KeepAliveServer < WEBrick::HTTPServer
  class KeepAliveApp < WEBrick::HTTPServlet::AbstractServlet
    SOCKS = [].freeze

    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res["Connection"] = "Keep-Alive"
      res["Keep-Alive"] = "max=2"
      res["Content-Type"] = "application/json"
      res.body = "{\"counter\": 2}"
    end
  end

  def initialize(options = {})
    super({
      :BindAddress => "127.0.0.1",
      :Port => 0,
      :AccessLog => File.new(File::NULL),
      :Logger => Logger.new(File::NULL),
    }.merge(options))
    mount("/", KeepAliveApp)
  end

  def origin
    sock = listeners.first
    _, sock, ip, _ = sock.addr
    "http://#{ip}:#{sock}"
  end
end
