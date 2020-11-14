# frozen_string_literal: true

require "socket"
require "httpx/io/tcp"
require "httpx/io/unix"
require "httpx/io/udp"

if RUBY_ENGINE == "jruby"
  begin
    require "httpx/io/tls"
  rescue LoadError
    require "httpx/io/ssl"
  end
else
  require "httpx/io/ssl"
end

module HTTPX
  module IO
    extend Registry
    register "tcp", TCP
    register "ssl", SSL
    register "udp", UDP
    register "unix", HTTPX::UNIX
  end
end
