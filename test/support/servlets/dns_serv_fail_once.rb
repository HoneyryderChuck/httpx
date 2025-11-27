# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSServFailOnce < TestDNSResolver
  attr_reader :failed

  def initialize(*, **)
    super
    @failed = Hash.new(false)
  end

  private

  def dns_response(query)
    domain = extract_domain(query)
    return super if @failed[domain]

    @failed[domain] = true

    dns_error_response(query, 2)
  end
end
