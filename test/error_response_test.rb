# frozen_string_literal: true

require_relative "test_helper"

class ErrorResponseTest < Minitest::Test
  include HTTPX

  def test_error_response_status
    r1 = ErrorResponse.new(request_mock, RuntimeError.new("wow"), {})
    assert r1.status == "wow"
  end

  def test_error_response_error
    error = RuntimeError.new("wow")
    r1 = ErrorResponse.new(request_mock, error, {})
    assert r1.error == error
  end

  def test_error_response_raise_for_status
    some_error = Class.new(RuntimeError)
    r1 = ErrorResponse.new(request_mock, some_error.new("wow"), {})
    assert_raises(some_error) { r1.raise_for_status }
  end

  def test_error_response_to_s
    r = ErrorResponse.new(request_mock, RuntimeError.new("wow"), {})
    str = r.to_s
    assert str.match(/wow \(.*RuntimeError.*\)/), "expected \"wow (RuntimeError)\" in \"#{str}\""
  end

  private

  def request_mock
    Request.new("GET", "http://example.com/")
  end
end
