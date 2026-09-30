# frozen_string_literal: true

require_relative "test"

class ByIpCertServer < TestServer
  def initialize(options = {})
    super(options.merge(
      tls: true,
      :BindAddress => HTTPX::Resolver.supported_ip_families.size > 1 ? "::1" : "127.0.0.1",
    ))
    mount_proc("/") do |_req, res|
      res.status = 200
      res.body = "hello"
    end
  end
end
