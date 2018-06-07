# frozen_string_literal: true

require "socket"
require "httpx/io/tcp"
require "httpx/io/ssl"
require "httpx/io/unix"

module HTTPX
  module IO
    extend Registry
    register "tcp", TCP
    register "ssl", SSL
    register "unix", HTTPX::UNIX
  end
end
