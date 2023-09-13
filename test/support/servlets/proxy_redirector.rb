# frozen_string_literal: true

require "webrick/httpproxy"
require_relative "test"

class ProxyServer < WEBrick::HTTPProxyServer
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
end

class ProxyRedirectorServer < TestServer
  def initialize(proxy, options = {})
    @proxy = proxy.to_s
    @proxy_port = proxy.port
    super(options)

    mount_proc("/") do |req, res|
      via = req.header["via"]
      if !via.empty? && via.any? { |v| v.include?(@proxy_port.to_s) }
        res.status = 200
        res.body = @proxy
      else
        res.set_redirect(WEBrick::HTTPStatus::UseProxy, @proxy)
      end
    end
  end
end
