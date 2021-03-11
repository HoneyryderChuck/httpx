# frozen_string_literal: true

module Requests
  module IO
    unless defined?(HTTPX::TLS)
      using HTTPX::URIExtensions

      def test_http_io
        io = origin_io
        uri = build_uri("/get")
        response = HTTPX.get(uri, io: io)
        verify_status(response, 200)
        verify_body_length(response)
        assert !io.closed?, "io should have been left open"
      ensure
        io.close if io
      end

      def test_http_io_hash
        io = origin_io
        uri = build_uri("/get")
        response = HTTPX.get(uri, io: { URI(origin).authority => io })
        verify_status(response, 200)
        verify_body_length(response)
        assert !io.closed?, "io should have been left open"
      ensure
        io.close if io
      end
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
      ctx.alpn_protocols = %w[h2 http/1.1] if ctx.respond_to?(:alpn_protocols)
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
