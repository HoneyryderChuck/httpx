# frozen_string_literal: true

require "simplecov" if ENV.key?("CI")

gem "minitest"
require "minitest/autorun"

if ENV.key?("PARALLEL")
  require "minitest/hell"
  class Minitest::Test
    parallelize_me!
  end
end

require "httpx"

Dir[File.join(".", "test", "support", "*.rb")].sort.each { |f| require f }
Dir[File.join(".", "test", "support", "**", "*.rb")].sort.each { |f| require f }

# Ruby 2.3 openssl configuration somehow ignores SSL_CERT_FILE env var.
# This adds it manually.
OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.add_file(ENV["SSL_CERT_FILE"]) if RUBY_VERSION.start_with?("2.3") && ENV.key?("SSL_CERT_FILE")

# 9090 drops SYN packets for connect timeout tests, make sure there's a server binding there.
CONNECT_TIMEOUT_PORT = ENV.fetch("CONNECT_TIMEOUT_PORT", 9090).to_i

server = TCPServer.new("127.0.0.1", CONNECT_TIMEOUT_PORT)

Thread.start do
  begin
    sock = server.accept
    warn "received: #{sock}"
    sock.close
  rescue StandardError => e
    puts "smth weird happened: #{e.class} -> #{e.message}"
    puts e.backtrace
  end
end
