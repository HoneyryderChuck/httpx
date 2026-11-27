# frozen_string_literal: true

require "digest"
require_relative "test"

class HedgingServer < TestServer
  class HedgingApp < WEBrick::HTTPServlet::AbstractServlet
    def initialize(server, hits, first_delay, hedge_delay, drop_first, **kw)
      super(server, **kw)
      @hits = hits
      @first_delay = first_delay
      @hedge_delay = hedge_delay
      @drop_first = drop_first
    end

    def do_GET(req, res) # rubocop:disable Naming/MethodName
      body = req.body || "".b
      first = @hits.hit(req.path) == 1

      if first && !req.path.start_with?("/fast/")
        sleep @first_delay

        if @drop_first
          req.instance_variable_get(:@socket).close
          raise WEBrick::HTTPStatus::EOFError
        end
      else
        sleep @hedge_delay
      end

      res.status = 200
      res["Content-Type"] = "application/json"
      res.body = JSON.dump(
        "bytes" => body.bytesize,
        "sha256" => Digest::SHA256.hexdigest(body),
        "first" => first,
        "client_port" => req.peeraddr[1],
      )
    end

    def do_POST(req, res) # rubocop:disable Naming/MethodName
      do_GET(req, res)
    end
  end

  class Hits
    def initialize
      @hits = Hash.new(0)
      @lock = Thread::Mutex.new
    end

    def hit(path)
      @lock.synchronize { @hits[path] += 1 }
    end
  end

  def initialize(first_delay: 3, hedge_delay: 0, drop_first: false, **options)
    super(options)
    mount("/", HedgingApp, Hits.new, first_delay, hedge_delay, drop_first)
  end
end
