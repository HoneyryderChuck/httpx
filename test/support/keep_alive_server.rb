# frozen_string_literal: true

require "webrick"
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

class KeepAliveServer < TestServer
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
    super
    mount("/", KeepAliveApp)
  end
end

class NoExpect100Server < TestServer
  class NoExpect100App < WEBrick::HTTPServlet::AbstractServlet
    SOCKS = [].freeze

    def do_POST(req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "echo: #{req.body}"
    end
  end

  def initialize(options = {})
    super
    mount("/", NoExpect100App)
  end
end
