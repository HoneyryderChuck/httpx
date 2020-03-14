# frozen_string_literal: true

require "tempfile"
require_relative "../test_helper"

class UnixTest < Minitest::Test
  include HTTPHelpers

  def test_unix_session
    skip if RUBY_ENGINE == "jruby"
    on_unix_server do |path|
      response = HTTPX.with(transport: "unix", transport_options: { path: path }).get("http://unix.com/ping")
      verify_status(response, 200)
      assert response.to_s == "pong", "unexpected body (#{response})"
    end
  end

  private

  RESPONSE_HEADER = <<-HTTP.lines.map(&:strip).map(&:chomp).join("\r\n") << ("\r\n" * 2)
    HTTP/1.1 200 OK
    Date: Mon, 27 Jul 2009 12:28:53 GMT
    Content-Length: 4
    Content-Type: text/plain
    Connection: close
  HTTP

  def on_unix_server
    mutex = Mutex.new
    resource = ConditionVariable.new
    path = File.join(Dir.tmpdir, "httpx-unix.sock")
    server = UNIXServer.new(path)
    begin
      th = Thread.start do
        mutex.synchronize do
          resource.signal
        end
        socket = server.accept
        socket.readpartial(4096) # drain the socket for the request
        socket.write(RESPONSE_HEADER)
        socket.write("pong")
        socket.close
      end
      mutex.synchronize do
        resource.wait(mutex)
      end
      yield server.path
    ensure
      server.close
      File.unlink(path)
      th.terminate
    end
  end
end
