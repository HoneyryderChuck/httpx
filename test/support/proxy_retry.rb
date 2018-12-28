# frozen_string_literal: true

module ProxyRetry
  def run(*)
    return super unless name.include?("_proxy")

    result = nil
    3.times.each do |_i|
      result = super
      break if result.passed?

      self.failures = []
      self.assertions = 0
    end
    result
  end
end

Minitest::Test.prepend(ProxyRetry) unless ENV.key?("HTTPX_DEBUG")
