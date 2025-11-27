# frozen_string_literal: true

require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSErrorServer < TestDNSResolver
  private

  def dns_response(query)
    dns_error_response(query, 4)
  end
end
