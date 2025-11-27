# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSNoAddress < TestDNSResolver
  private

  def resolve(*)
    []
  end
end
