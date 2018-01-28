module ProxyRetry
  def run(*)
    return super unless self.name.include?("_proxy")
    result = nil
    3.times.each do |i|
      result = super
      break if result.passed?
      self.failures = []
      self.assertions = 0
    end
    result
  end
end

Minitest::Test.prepend(ProxyRetry) unless ENV.key?("HTTPX_DEBUG")
