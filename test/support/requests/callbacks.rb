# frozen_string_literal: true

require "resolv"

module Requests
  using HTTPX::URIExtensions
  module Callbacks
    def test_callbacks_connection_opened
      uri = URI(build_uri("/get"))
      origin = ip = nil

      response = HTTPX.plugin(SessionWithPool).on_connection_opened do |o, sock|
        origin = o
        ip = sock.to_io.remote_address.ip_address
      end.get(uri)
      verify_status(response, 200)

      assert !origin.nil?
      assert origin.to_s == uri.origin
      assert !ip.nil?

      assert Resolv.getaddresses(uri.host).include?(ip)
    end

    def test_callbacks_connection_closed
      uri = URI(build_uri("/get"))
      origin = nil

      response = HTTPX.plugin(SessionWithPool).on_connection_closed do |o|
        origin = o
      end.get(uri)
      verify_status(response, 200)

      assert !origin.nil?
      assert origin.to_s == uri.origin
    end

    def test_callbacks_request_error
      uri = URI(build_uri("/get"))
      error = nil

      http = HTTPX.on_request_error { |_, err| error = err }

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

    def test_callbacks_request
      uri = URI(build_uri("/post"))
      started = completed = false
      chunks = 0

      http = HTTPX.on_request_started { |_| started = true }
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

      http = HTTPX.on_response_started { |_, _| started = true }
                  .on_response_body_chunk { |_, _, _chunk| chunks += 1 }
                  .on_response_completed { |_, _| completed = true }

      response = http.get(uri)
      verify_status(response, 200)

      assert started
      assert completed
      assert chunks.positive?
    end
  end
end
