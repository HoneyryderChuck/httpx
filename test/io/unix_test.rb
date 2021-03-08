# frozen_string_literal: true

require "tempfile"
require_relative "../test_helper"

class UnixTest < Minitest::Test
  include HTTPHelpers

  using HTTPX::URIExtensions

  unless RUBY_ENGINE == "jruby"
    def test_unix_session
      on_unix_server(__method__) do |path|
        HTTPX.with(transport: "unix", addresses: [path]).wrap do |http|
          http.get("http://unix.com/ping", "http://unix.com/ping").each do |response|
            verify_status(response, 200)
            assert response.to_s == "pong", "unexpected body (#{response})"
          end
        end
      end
    end

    def test_unix_session_io
      on_unix_server(__method__) do |path|
        io = UNIXSocket.new(path)
        HTTPX.with(transport: "unix", io: io).wrap do |http|
          response = http.get("http://unix.com/ping")
          verify_status(response, 200)
          assert response.to_s == "pong", "unexpected body (#{response})"
        end
        assert io.eof?, "io should have been used and closed (by the server)"
        io.close
      end
    end

    def test_unix_session_io_hash
      on_unix_server(__method__) do |path|
        io = UNIXSocket.new(path)
        uri = URI("http://unix.com/ping")
        HTTPX.with(transport: "unix", io: { uri.authority => io }).wrap do |http|
          response = http.get(uri)
          verify_status(response, 200)
          assert response.to_s == "pong", "unexpected body (#{response})"
        end
        assert io.eof?, "io should have been used and closed (by the server)"
        io.close
      end
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

  def on_unix_server(sockname)
    mutex = Mutex.new
    resource = ConditionVariable.new
    path = File.join(Dir.tmpdir, "httpx-unix-#{sockname}.sock")
    server = UNIXServer.new(path)
    begin
      th = Thread.start do
        mutex.synchronize do
          resource.signal
        end

        loop do
          begin
            socket = server.accept
            socket.readpartial(4096) # drain the socket for the request
            socket.write(RESPONSE_HEADER)
            socket.write("pong")
            socket.close
          rescue IOError
            break
          end
        end
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
