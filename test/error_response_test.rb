# frozen_string_literal: true

require_relative "test_helper"

class ErrorResponseTest < Minitest::Test
  include HTTPX

  def test_error_response_status
    r1 = ErrorResponse.new(request_mock, RuntimeError.new("wow"), {})
    assert r1.status == "wow"
  end

  def test_error_response_raise_for_status
    some_error = Class.new(RuntimeError)
    r1 = ErrorResponse.new(request_mock, some_error.new("wow"), {})
    assert_raises(some_error) { r1.raise_for_status }
  end

  def test_error_response_respond_method_missing_errors
    r1 = ErrorResponse.new(request_mock, RuntimeError.new("wow"), {})
    ex1 = assert_raises(NoMethodError) { r1.read }
    assert ex1.message =~ /undefined response method/
    ex2 = assert_raises(NoMethodError) { r1.bang }
    assert ex2.message =~ /undefined method/
  end

  def test_error_response_to_s
    r = ErrorResponse.new(request_mock, RuntimeError.new("wow"), {})
    str = r.to_s
    assert str.match(/wow \(.*RuntimeError.*\)/), "expected \"wow (RuntimeError)\" in \"#{str}\""
  end

  private

  def request_mock
    Request.new(:get, "http://example.com/")
  end
end
