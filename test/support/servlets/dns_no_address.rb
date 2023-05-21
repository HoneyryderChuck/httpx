# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSNoAddress < TestDNSResolver
  private

  def dns_response(query)
    domain = extract_domain(query)
    ip = Resolv.getaddress(domain)
    cname = ip =~ /[a-z]/

    # Valid response header
    response = "#{query[0, 2]}\x81\x00#{query[4, 2]}\x00\x00\x00\x00\x00\x00".b

    # Append original question section
    response << query[12..-1].b

    # Use pointer to refer to domain name in question section
    response << "\xc0\x0c".b
    response
  end
end
