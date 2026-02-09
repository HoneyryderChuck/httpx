# frozen_string_literal: true

require "test_helper"

class Bug_1_7_2_2_Test < Minitest::Test
  include HTTPHelpers
  include FiberSchedulerTestHelpers

  def test_fiber_persistent_should_not_account_retry_on_separate_close
    responses = []
    session = HTTPX.plugin(RequestInspector)
                   .plugin(:persistent, max_retries: 1)
                   .with(timeout: { request_timeout: 3 }, resolver: { cache: false })

    with_test_fiber_scheduler do
      3.times.map do
        Fiber.schedule do
          responses << session.get(build_uri("/delay/10"))
        end
      end
    end

    responses.each do |response|
      verify_error_response(response, HTTPX::RequestTimeoutError)
    end
    assert session.calls == 5, "expect requests to be retried 6 times (was #{session.calls})"
  end if RUBY_VERSION >= "4.0.0"

  private

  def scheme
    "http://"
  end
end
