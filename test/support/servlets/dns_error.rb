# frozen_string_literal: true

require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSErrorServer < TestDNSResolver
  private

  def response_header(query)
    "#{query[0, 2]}\x81\x02#{query[4, 2]}\x00\x00\x00\x00\x00\x00".b
  end
end
