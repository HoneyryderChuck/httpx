# frozen_string_literal: true

require_relative "test_helper"

class ResponseTest < Minitest::Test
  include HTTPX

  def test_response_status
    r1 = Response.new(request, 200, "1.1", {})
    assert r1.status == 200, "unexpected status code (#{r1.status})"
    r2 = Response.new(request, "200", "1.1", {})
    assert r2.status == 200, "unexpected status code (#{r2.status})"
  end

  def test_response_headers
    assert resource.headers.is_a?(Headers), "headers should have been coerced"
  end

  def test_raise_for_status
    r1 = Response.new(request, 200, "2.0", {})
    r1.raise_for_status
    r2 = Response.new(request, 302, "2.0", {})
    r2.raise_for_status
    r3 = Response.new(request, 404, "2.0", {})
    error = assert_raises(HTTPX::HTTPError) { r3.raise_for_status }
    assert error.status == 404
    r4 = Response.new(request, 500, "2.0", {})
    error = assert_raises(HTTPX::HTTPError) { r4.raise_for_status }
    assert error.status == 500
  end

  def test_response_body_to_s
    body1 = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body1.write("foo")
    assert body1 == "foo", "body must be updated"
    body2 = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body2.write("foo")
    body2.write("bar")
    assert body2 == "foobar", "body must buffer subsequent chunks"

    body3 = response_body(Response.new(request("head"), 200, "2.0", {}), threshold_size: 1024)
    assert body3 == "", "HEAD requets body must be empty"
  end

  def test_response_body_copy_to_memory
    payload = "a" * 512
    body = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body.write(payload)

    memory = StringIO.new
    body.copy_to(memory)
    assert memory.string == payload, "didn't copy all bytes (expected #{payload.bytesize}, was #{memory.size})"
    body.close
  end

  def test_response_body_copy_to_file
    payload = "a" * 2048
    body = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body.write(payload)

    file = Tempfile.new("httpx-file-buffer")
    body.copy_to(file)
    assert File.read(file.path) == payload, "didn't copy all bytes (expected #{payload.bytesize}, was #{File.size(file.path)})"
    body.close
    file.unlink
  end

  def test_response_body_read
    body1 = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body1.write("foo")
    assert body1.bytesize == 3
    assert body1.read(1), "f"
    assert body1.read(1), "o"
    assert body1.read(1), "o"
  end

  def test_response_body_each
    body1 = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body1.write("foo")
    assert body1.each.to_a == %w[foo], "must yield buffer"
    body2 = response_body(Response.new(request, 200, "2.0", {}), threshold_size: 1024)
    body2.write("foo")
    body2.write("bar")
    assert body2.each.to_a == %w[foobar], "must yield buffers"
  end

  def test_response_body_buffer
    buffer = Response::Body::Buffer.new(10)
    buffer.extend(Module.new do
      attr_reader :buffer
    end)
    assert buffer.buffer.nil?, "body should not buffer anything"
    buffer << "hello"
    assert buffer.buffer.is_a?(StringIO), "body should buffer to memory"
    buffer << " world"
    assert buffer.buffer.is_a?(Tempfile), "body should buffer to file after going over threshold"
  end

  private

  def request(verb = :get, uri = "http://google.com")
    Request.new(verb, uri)
  end

  def response(*args)
    Response.new(*args)
  end

  def resource
    @resource ||= Response.new(request, 200, "2.0", {})
  end

  def response_body(response, pool: mock_pool, **params)
    body = Response::Body.new(response, **params)
    pool.body = body
    body.pool = pool
    body
  end

  def mock_pool
    Class.new do
      attr_writer :body

      def next_tick
        @body.finish!
      end
    end.new
  end
end
