# frozen_string_literal: true

require_relative "test"

class ByIpCertServer < TestServer
  USE_IPV6 = HTTPX::Options::DEFAULT_OPTIONS[:ip_families].size > 1
  CERTS_DIR = File.expand_path("../ci/certs", __dir__)

  def initialize
    cert = OpenSSL::X509::Certificate.new(File.read(File.join(CERTS_DIR, "localhost-server.crt")))
    key = OpenSSL::PKey.read(File.read(File.join(CERTS_DIR, "localhost-server.key")))
    super(
      :BindAddress => USE_IPV6 ? "::1" : "127.0.0.1",
      :SSLEnable => true,
      :SSLCertificate => cert,
      :SSLPrivateKey => key,
    )
    mount_proc("/") do |_req, res|
      res.status = 200
      res.body = "hello"
    end
  end
end
