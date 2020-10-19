# frozen_string_literal: true

if ENV.key?("CI")
  require "simplecov"
  SimpleCov.command_name "#{RUBY_ENGINE}-#{RUBY_VERSION}"
  SimpleCov.coverage_dir "coverage/#{RUBY_ENGINE}-#{RUBY_VERSION}"
end

gem "minitest"
require "minitest/autorun"

if ENV.key?("PARALLEL")
  require "minitest/hell"
  class Minitest::Test
    parallelize_me!
  end
end

require "httpx"

Dir[File.join(".", "lib", "httpx", "plugins", "**", "*.rb")].sort.each { |f| require f } if defined?(RBS)

Dir[File.join(".", "test", "support", "*.rb")].sort.each { |f| require f }
Dir[File.join(".", "test", "support", "**", "*.rb")].sort.each { |f| require f }

# Ruby 2.3 openssl configuration somehow ignores SSL_CERT_FILE env var.
# This adds it manually.
OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE.add_file(ENV["SSL_CERT_FILE"]) if RUBY_VERSION.start_with?("2.3") && ENV.key?("SSL_CERT_FILE")

module SessionWithPool
  ConnectionPool = Class.new(HTTPX::Pool) do
    attr_reader :connections
    attr_reader :connection_count
    attr_reader :ping_count

    def initialize(*)
      super
      @connection_count = 0
      @ping_count = 0
    end

    def init_connection(connection, _)
      super
      connection.on(:open) { @connection_count += 1 }
      connection.on(:pong) { @ping_count += 1 }
    end
  end

  module InstanceMethods
    def pool
      @pool ||= ConnectionPool.new
    end
  end

  module ConnectionMethods
    def set_parser_callbacks(parser)
      super
      parser.on(:pong) { emit(:pong) }
    end
  end
end

# 9090 drops SYN packets for connect timeout tests, make sure there's a server binding there.
CONNECT_TIMEOUT_PORT = ENV.fetch("CONNECT_TIMEOUT_PORT", 9090).to_i

server = TCPServer.new("127.0.0.1", CONNECT_TIMEOUT_PORT)

Thread.start do
  begin
    sock = server.accept
    sock.close
  rescue StandardError => e
    warn e.message
    warn e.backtrace
  end
end
