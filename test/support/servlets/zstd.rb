# frozen_string_literal: true

require "zstd-ruby"
require_relative "test"

class ZstdServer < TestServer
  class ZstdApp < WEBrick::HTTPServlet::AbstractServlet
    BODY = "{\"zstd\":true,\"message\":\"hello world\"}"

    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = Zstd.compress(BODY)
      res["Content-Type"] = "application/json"
      res["Content-Encoding"] = "zstd"
    end
  end

  def initialize(options = {})
    super
    mount("/", ZstdApp)
  end
end
