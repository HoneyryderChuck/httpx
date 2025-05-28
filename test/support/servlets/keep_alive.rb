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

class KeepAlivePongThenGoawayServer < TestHTTP2Server
  attr_reader :pings, :pongs

  def initialize(**)
    @sent = Hash.new(false)
    super()
  end

  private

  def handle_stream(conn, stream)
    # responds once, then closes the connection
    if @sent[conn]
      conn.goaway
      @sent[conn] = false
    else
      super
      @sent[conn] = true
    end
  end
end

class KeepAlivePongThenCloseSocketServer < TestHTTP2Server
  def initialize
    @sent = false
    super
  end

  private

  def handle_connection(conn, sock)
    super
    conn.on(:stream) do |stream|
      stream.on(:close) do
        @sent = true
        close_socket(sock)
      end
    end
  end
end

class KeepAlivePongThenTimeoutSocketServer < TestHTTP2Server
  def initialize(interval: 10, **args)
    @interval = interval
    super(**args)
  end

  private

  def handle_connection(conn, sock)
    super
    conn.on(:stream) do |stream|
      stream.on(:close) do
        sleep(@interval)
      end
    end
  end
end
