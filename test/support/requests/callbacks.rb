# frozen_string_literal: true

require "resolv"
require "socket"
require "httpx/plugins/callbacks"

module Requests
  using HTTPX::URIExtensions
  module Callbacks
    def test_callbacks_connection_opened
      uri = URI(build_uri("/get"))
      origin = ip = nil
      opened = 0

      response = HTTPX.plugin(SessionWithPool).plugin(:callbacks).on_connection_opened do |o, sock|
        origin = o
        ip = sock.to_io.remote_address.ip_address
        opened += 1
      end.get(uri)
      verify_status(response, 200)

      assert !origin.nil?
      assert origin.to_s == uri.origin
      assert !ip.nil?
      assert opened == 1

      assert Resolv.getaddresses(uri.host).include?(ip)
    end

    def test_callbacks_connection_closed
      uri = URI(build_uri("/get"))
      origin = nil
      closed = 0

      error = :unset

      response = HTTPX.plugin(SessionWithPool).plugin(:callbacks).on_connection_closed do |o, err|
        origin = o
        error = err
        closed += 1
      end.get(uri)
      verify_status(response, 200)

      assert !origin.nil?
      assert origin.to_s == uri.origin
      assert closed == 1
      # clean closes do not carry an error
      assert error.nil?
    end

    def test_callbacks_connection_closed_yields_error
      skip if tls?

      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        sock = server.accept
        sock.readpartial(2048)
        sock.close
      end

      _, port, ip, = server.addr
      uri = "http://#{ip}:#{port}/"

      origin = error = nil
      closed = 0

      response = HTTPX.plugin(SessionWithPool).plugin(:callbacks).on_connection_closed do |o, err|
        origin = o
        error = err
        closed += 1
      end.get(uri)

      assert response.is_a?(HTTPX::ErrorResponse)
      assert closed == 1
      assert origin.to_s == uri.chomp("/")
      assert error.is_a?(StandardError), "expected an error, got #{error.inspect}"
    ensure
      thread&.join(1)
      server&.close
    end

    def test_callbacks_connection_closed_error_does_not_leak
      skip if tls?

      errors = []
      http = HTTPX.plugin(SessionWithPool).plugin(:callbacks).on_connection_closed { |_, err| errors << err }

      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        sock = server.accept
        sock.readpartial(2048)
        sock.close
      end

      _, port, ip, = server.addr
      http.get("http://#{ip}:#{port}/")
      thread.join(1)

      assert errors.size == 1 && !errors.first.nil?

      ok_server = TCPServer.new("127.0.0.1", 0)
      ok_thread = Thread.new do
        sock = ok_server.accept
        sock.readpartial(2048)
        sock.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        sock.close
      end

      _, ok_port, ok_ip, = ok_server.addr
      response = http.get("http://#{ok_ip}:#{ok_port}/")

      assert response.status == 200
      assert errors.size == 2
      assert errors.last.nil?
    ensure
      ok_thread&.join(1)
      ok_server&.close
      server&.close
    end

    def test_callbacks_connection_closed_not_called_on_inactive_connections
      skip if tls?

      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        sock = server.accept
        sock.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok") while sock.readpartial(2048)
      rescue IOError
        sock&.close
      end

      _, port, ip, = server.addr
      uri = "http://#{ip}:#{port}/"

      closed = []
      http = HTTPX.plugin(SessionWithPool).plugin(:persistent).plugin(:callbacks)
                  .on_connection_closed { |_, _, connection:| closed << connection.state }

      2.times { verify_status(http.get(uri), 200) }
      assert closed.empty?, "expected no close for kept-alive connections, got #{closed.inspect}"

      http.close
      assert closed == [:closed]
    ensure
      thread&.join(1)
      server&.close
    end

    def test_callbacks_connection_opened_and_closed_yield_connection
      uri = URI(build_uri("/get"))
      opened = closed = nil

      response = HTTPX.plugin(SessionWithPool).plugin(:callbacks)
                      .on_connection_opened { |_, _, connection:| opened = connection }
                      .on_connection_closed { |_, _, connection:| closed = connection }
                      .get(uri)
      verify_status(response, 200)

      assert opened.is_a?(HTTPX::Connection)
      assert closed.equal?(opened), "close must yield the same connection object which was opened"
      assert opened.origin.to_s == uri.origin
    end

    def test_callbacks_request_and_response_yield_connection
      uri = URI(build_uri("/post"))
      opened = nil
      seen = {}

      http = HTTPX.plugin(SessionWithPool).plugin(:callbacks)
                  .on_connection_opened { |_, _, connection:| opened = connection }
                  .on_request_started { |_, connection:| seen[:request_started] = connection }
                  .on_request_body_chunk { |_, _, connection:| seen[:request_body_chunk] = connection }
                  .on_request_completed { |_, connection:| seen[:request_completed] = connection }
                  .on_response_started { |_, _, connection:| seen[:response_started] = connection }
                  .on_response_body_chunk { |_, _, _, connection:| seen[:response_body_chunk] = connection }
                  .on_response_completed { |_, _, connection:| seen[:response_completed] = connection }

      response = http.post(uri, body: "data")
      verify_status(response, 200)

      assert opened.is_a?(HTTPX::Connection)
      %i[request_started request_body_chunk request_completed response_started response_body_chunk response_completed].each do |cb|
        assert seen[cb].equal?(opened), "#{cb} did not yield the connection the request was sent on (got #{seen[cb].inspect})"
      end
    end

    def test_callbacks_request_error_yields_connection
      skip if tls?

      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        sock = server.accept
        sock.readpartial(2048)
        sock.close
      end

      _, port, ip, = server.addr
      opened = yielded = nil

      response = HTTPX.plugin(SessionWithPool).plugin(:callbacks)
                      .on_connection_opened { |_, _, connection:| opened = connection }
                      .on_request_error { |_, _, connection:| yielded = connection }
                      .get("http://#{ip}:#{port}/")

      assert response.is_a?(HTTPX::ErrorResponse)
      assert opened.is_a?(HTTPX::Connection)
      assert yielded.equal?(opened)
    ensure
      thread&.join(1)
      server&.close
    end

    def test_callbacks_request_error
      uri = URI(build_uri("/get"))
      error = nil

      http = HTTPX.plugin(:callbacks).on_request_error { |_, err| error = err }

      response = http.get(uri)
      verify_status(response, 200)

      assert error.nil?

      unavailable_host = URI(origin("localhost"))
      unavailable_host.port = next_available_port
      response = http.get(unavailable_host.to_s)
      verify_error_response(response, /Connection refused| not available/)

      assert !error.nil?
      assert error == response.error
    end

    def test_callbacks_request_error_allow_reraise_in_bock
      URI(build_uri("/get"))
      err_type = Class.new(StandardError)

      ex = assert_raises(err_type) do
        http = HTTPX.plugin(:callbacks).on_request_error do |_, err|
          raise err_type, err.message
        end
        # unavailable_host = URI(origin("localhost"))
        # unavailable_host.port = next_available_port
        # http.get(unavailable_host.to_s)
        http.get("http://unknownhost")
      end
      assert ex.message == "name or service not known"
    end

    def test_callbacks_request
      uri = URI(build_uri("/post"))
      started = completed = false
      chunks = 0

      http = HTTPX.plugin(:callbacks)
                  .on_request_started { |_| started = true }
                  .on_request_body_chunk { |_, _chunk| chunks += 1 }
                  .on_request_completed { |_| completed = true }

      response = http.post(uri, body: "data")
      verify_status(response, 200)

      assert started
      assert completed
      assert chunks.positive?
    end

    def test_callbacks_response
      uri = URI(build_uri("/get"))
      started = completed = false
      chunks = 0

      http = HTTPX.plugin(:callbacks)
                  .on_response_started { |_, _| started = true }
                  .on_response_body_chunk { |_, _, _chunk| chunks += 1 }
                  .on_response_completed { |_, _| completed = true }

      response = http.get(uri)
      verify_status(response, 200)

      assert started
      assert completed
      assert chunks.positive?
    end

    def test_callbacks_on_body_chunk_raises_error
      uri = URI(build_uri("/post"))

      http = HTTPX.plugin(:callbacks)
                  .on_request_body_chunk { |_, _chunk| raise "ups" }

      ex = assert_raises do
        http.post(uri, body: "data")
      end
      assert ex.message == "ups"
    end

    def test_callbacks_keeps_callbacks_when_building_new_sessions
      http = HTTPX.plugin(:callbacks).on_request_started { puts "test" }
      http.singleton_class.class_eval do
        public :callbacks_for?
      end

      assert http.callbacks_for?(:request_started)
      http = http.with(headers: { a: 1 })
      assert http.callbacks_for?(:request_started)
    end

    def test_callbacks_keeps_callbacks_with_other_plugins
      http = HTTPX.plugin(:callbacks).on_request_started { puts "test" }
                  .plugin(:auth)

      http.singleton_class.class_eval do
        public :callbacks_for?
      end

      assert http.callbacks_for?(:request_started)
    end

    %i[
      connection_opened connection_closed
      request_started request_completed
      response_started response_body_chunk response_completed
    ].each do |callback|
      define_method :"test_callbacks_bug_inside_#{callback}_callback" do
        assert_raises(NameError) do
          HTTPX.plugin(SessionWithPool).plugin(:callbacks).send(:"on_#{callback}") { i_dont_exist }.get(build_uri("/get"))
        end
      end
    end

    def test_callbacks_can_compose_with
      http = HTTPX.plugin(:callbacks).with(persistent: true)
      assert http.instance_variable_get(:@persistent)
    end
  end
end
