# frozen_string_literal: true

require "socket"
require "httpx/io/tcp"
require "httpx/io/unix"
require "httpx/io/udp"

module HTTPX
  module IO
    extend Registry
    register "udp", UDP
    register "unix", HTTPX::UNIX
    register "tcp", TCP

    if RUBY_ENGINE == "jruby"
      begin
        require "httpx/io/tls"
        register "ssl", TLS
      rescue LoadError
        # :nocov:
        require "httpx/io/ssl"
        register "ssl", SSL
        # :nocov:
      end
    else
      require "httpx/io/ssl"
      register "ssl", SSL
    end
  end
end
