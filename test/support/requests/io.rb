# frozen_string_literal: true

module Requests
  module IO
    def test_http_io
      io = origin_io
      uri = build_uri("/")
      response = HTTPX.get(uri, io: io)
      assert response.status == 200, "status is unexpected"
      assert response.body.to_s.bytesize == response.headers["content-length"].to_i, "didn't load the whole body"
      assert !io.closed?, "io should have been left open"
    ensure
      io.close if io
    end
  end

  private

  def origin_io
    uri = URI(origin)
    case uri.scheme
    when "http"
      TCPSocket.new(uri.host, uri.port)
    when "https"
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.alpn_protocols = %w[h2 http/1.1]
      sock = OpenSSL::SSL::SSLSocket.new(TCPSocket.new(uri.host, uri.port), ctx)
      sock.hostname = uri.host
      sock.sync_close = true
      sock.connect
      sock
    else
      raise "#{uri.scheme}: unsupported scheme"
    end
  end


end 
