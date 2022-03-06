# frozen_string_literal: true

require "socket"
require "httpx/io/udp"
require "httpx/io/tcp"
require "httpx/io/unix"
require "httpx/io/ssl"

module HTTPX
  module IO
    extend Registry
    register "udp", UDP
    register "unix", HTTPX::UNIX
    register "tcp", TCP
    register "ssl", SSL
  end
end
