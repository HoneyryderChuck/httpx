# frozen_string_literal: true

require_relative "test"

class ResponseCacheServer < TestServer
  class NoCacheApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "no-cache"
      res["Cache-Control"] = "private, no-store"
    end
  end

  def initialize(options = {})
    super
    mount("/no-store", NoCacheApp)
  end
end
