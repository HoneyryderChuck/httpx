# frozen_string_literal: true

module ResponseHelpers
  private

  def verify_status(response, expect)
    raise response.error if response.is_a?(HTTPX::ErrorResponse)

    assert response.status == expect, "status assertion failed: #{response.status} (expected: #{expect})"
  end

  %w[header param].each do |meth|
    class_eval <<-DEFINE, __FILE__, __LINE__ + 1
      def verify_#{meth}(#{meth}s, key, expect)
        assert #{meth}s.key?(key), "#{meth}s don't contain the given key (\"\#{key}\", headers: \#{#{meth}s})"
        value = #{meth}s[key]
        if value.respond_to?(:start_with?)
          assert value.start_with?(expect), "#{meth} assertion failed: \#{key}=\#{value} (expected: \#{expect}})"
        else
          assert value == expect, "#{meth} assertion failed: \#{key}=\#{value.to_s} (expected: \#{expect.to_s})"
        end
      end

      def verify_no_#{meth}(#{meth}s, key)
        assert !#{meth}s.key?(key), "#{meth}s contains the given key (" + key + ": \#{#{meth}s[key]})"
      end
    DEFINE
  end

  def verify_body_length(response, expect = response.headers["content-length"].to_i)
    len = response.body.to_s.bytesize
    assert len == expect, "length assertion failed: #{len} (expected: #{expect})"
  end

  def verify_execution_delta(expected, actual, delta = 0)
    assert_in_delta expected, actual, delta, "expected to have executed in #{expected} secs (actual: #{actual} secs)"
  end

  def verify_error_response(response, expectation = nil)
    assert response.is_a?(HTTPX::ErrorResponse), "expected an error response (instead got: #{response.inspect})"

    return unless expectation

    case expectation
    when Regexp
      assert response.error.message =~ expectation,
             "expected to match \/#{expectation}\/ in \"#{response.error.message}\""
    when String
      assert response.error.message.include?(expectation),
             "expected \"#{response.error.message}\" to include \"#{expectation}\""
    when Class
      assert response.error.is_a?(expectation) || response.error.cause.is_a?(expectation),
             "expected #{response.error} to be a #{expectation}"
    else
      raise "unexpected expectation (#{expectation})"
    end
  end
end
