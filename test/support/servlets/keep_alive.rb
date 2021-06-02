# frozen_string_literal: true

require_relative "test"

class KeepAliveServer < TestServer
  class KeepAliveApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res["Connection"] = "Keep-Alive"
      res["Content-Type"] = "application/json"
      res.body = "{\"counter\": infinity}"
    end
  end

  class KeepAliveMax2App < WEBrick::HTTPServlet::AbstractServlet
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
    mount("/2", KeepAliveMax2App)
  end
end
