# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class SlowDNSServer < TestDNSResolver
  def initialize(timeout)
    @timeout = timeout
    super()
  end

  private

  def dns_response(*)
    sleep(@timeout)
    super
  end
end
