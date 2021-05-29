# frozen_string_literal: true

require_relative "test"

class Expect100Server < TestServer
  class DelayedExpect100App < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(req, res) # rubocop:disable Naming/MethodName
      query = WEBrick::HTTPUtils.parse_query(req.query_string)
      delay = (query["delay"] || 1).to_i
      sleep(delay)
      req.continue
      res.status = 200
      res.body = "echo: #{req.body}"
    end
  end

  class NoExpect100App < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "echo: #{req.body}"
    end
  end

  def initialize(options = {})
    super
    mount("/no-expect", NoExpect100App)
    mount("/delay", DelayedExpect100App)
  end
end
