# frozen_string_literal: true

require_relative "test_helper"

class ErrorResponseTest < Minitest::Test
  include HTTPX

  def test_response_status
    r1 = ErrorResponse.new(RuntimeError.new("wow"), {})
    assert r1.status == "wow"
  end

  def test_response_raise_for_status
    some_error = Class.new(RuntimeError)
    r1 = ErrorResponse.new(some_error.new("wow"), {})
    assert_raises(some_error) { r1.raise_for_status }
  end

  def test_respond_method_missing_errors
    r1 = ErrorResponse.new(RuntimeError.new("wow"), {})
    ex1 = assert_raises(NoMethodError) { r1.headers }
    assert ex1.message =~ /undefined response method/
    ex2 = assert_raises(NoMethodError) { r1.bang }
    assert ex2.message =~ /undefined method/
  end
end
