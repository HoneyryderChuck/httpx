# frozen_string_literal: true

require "socket"
require "httpx/io/tcp"
require "httpx/io/ssl"
require "httpx/io/unix"
require "httpx/io/udp"

module HTTPX
  module IO
    extend Registry
    register "tcp", TCP
    register "ssl", SSL
    register "udp", UDP
    register "unix", HTTPX::UNIX
  end
end
