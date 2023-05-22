# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSNoAddress < TestDNSResolver
  private

  def response_header(query)
    "#{query[0, 2]}\x81\x00#{query[4, 2]}\x00\x00\x00\x00\x00\x00".b
  end
end
