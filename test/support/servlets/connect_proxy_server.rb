# frozen_string_literal: true

require "webrick/httpproxy"
require_relative "test"

class ConnectProxyServer < WEBrick::HTTPProxyServer
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
    _, port, ip, _ = sock.addr
    URI::HTTP.build(host: ip, port: port)
  end

  def connect_requests
    @connect_requests ||= []
  end

  private

  def do_CONNECT(req, res) # rubocop:disable Naming/MethodName
    connect_requests << req.unparsed_uri
    super
  end
end
