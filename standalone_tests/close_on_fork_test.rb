# frozen_string_literal: true

require "oj"
require "test_helper"

class CloseOnForkTest < Minitest::Test
  include HTTPHelpers
  include HTTPX

  def test_close_on_fork_after_fork_callback
    skip("MRI feature") unless Process.respond_to?(:fork)
    GC.start # cleanup instances created by other tests

    http = HTTPX.plugin(SessionWithPool).with(persistent: true, close_on_fork: true)
    uri = URI(build_uri("/get"))
    response = http.get(uri)
    verify_status(response, 200)

    assert http.connections.size == 1
    assert http.connections.none? { |c| c.state == :closed }, "should have no closed connections"
    HTTPX::Session.after_fork
    assert http.connections.size == 1
    assert http.connections.one? { |c| c.state == :closed }, "should have a closed connection"
  end

  def test_close_on_fork_automatic_after_fork_callback
    skip("MRI 3.1 feature") unless Process.respond_to?(:_fork)
    GC.start # cleanup instances created by other tests

    http = HTTPX.plugin(SessionWithPool).with(persistent: true, close_on_fork: true)
    uri = URI(build_uri("/get"))
    response = http.get(uri)
    verify_status(response, 200)

    assert http.connections.size == 1
    assert http.connections.none? { |c| c.state == :closed }, "should have no closed connections"
    pid = fork do
      assert http.connections.one? { |c| c.state == :closed }, "should have no closed connections"
      exit!(0)
    end
    assert http.connections.none? { |c| c.state == :closed }, "should have no closed connections"
    _, status = Process.waitpid2(pid)
    assert_predicate(status, :success?)
  end

  private

  def scheme
    "https://"
  end

  def request(verb = "GET", uri = "http://google.com", **args)
    Request.new(verb, uri, Options.new, **args)
  end

  def response(*args)
    Response.new(*args)
  end
end
