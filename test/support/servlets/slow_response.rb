# frozen_string_literal: true

require_relative "test"

# Holds every response for +response_delay+ seconds. A batch capped at one in-flight request at a
# time therefore serializes into a queue of known length, with a local (and so consistently fast)
# handshake -- unlike the shared test server, where a slow connect or a mid-batch reset would make
# the queueing under test indistinguishable from the environment.
class SlowResponseServer < TestServer
  class SlowApp < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, response_delay, **kw)
      super(server, **kw)
      @response_delay = response_delay
    end

    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      sleep @response_delay

      res.status = 200
      res["Content-Type"] = "application/json"
      res.body = "{}"
    end
  end

  def initialize(response_delay: 1, **options)
    super(options)
    mount("/", SlowApp, response_delay)
  end
end
