# frozen_string_literal: true

require_relative "test_helper"

class PersistentTest < Minitest::Test
  include HTTPX

  def test_persistent_retries_change_request_failing_before_fully_written
    %i[idle headers body trailers].each do |state|
      request = request_in_state("POST", state)
      response = ErrorResponse.new(request, Errno::ECONNRESET.new)

      assert retryable?(request, response), "POST in #{state} state should be retryable on reconnectable errors"
    end
  end

  def test_persistent_does_not_retry_fully_written_change_request
    request = request_in_state("POST", :done)
    response = ErrorResponse.new(request, Errno::ECONNRESET.new)

    assert !retryable?(request, response), "fully written POST should not be retried"
  end

  def test_persistent_does_not_retry_change_request_on_non_reconnectable_error
    request = request_in_state("POST", :headers)
    response = ErrorResponse.new(request, RuntimeError.new("wow"))

    assert !retryable?(request, response), "POST should not be retried on non-reconnectable errors"
  end

  def test_persistent_retries_fully_written_idempotent_request
    request = request_in_state("GET", :done)
    response = ErrorResponse.new(request, Errno::ECONNRESET.new)

    assert retryable?(request, response), "fully written GET should still be retryable"
  end

  def test_persistent_retries_fully_written_change_request_when_opted_in
    session = HTTPX.plugin(:persistent, retry_change_requests: true)
    request = request_in_state("POST", :done, session)
    response = ErrorResponse.new(request, Errno::ECONNRESET.new)

    assert retryable?(request, response, session), "retry_change_requests should allow retrying fully written POST"
  end

  private

  def persistent_session
    @persistent_session ||= HTTPX.plugin(:persistent)
  end

  def retryable?(request, response, session = persistent_session)
    session.__send__(:retryable_request?, request, response, request.options)
  end

  def request_in_state(verb, state, session = persistent_session)
    request = session.build_request(verb, "http://example.com/", body: "data")
    request.instance_variable_set(:@state, state)
    request
  end
end
