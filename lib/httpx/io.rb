# frozen_string_literal: true

require "socket"
require "httpx/io/udp"
require "httpx/io/tcp"
require "httpx/io/unix"

begin
  require "httpx/io/ssl"
rescue LoadError
end
