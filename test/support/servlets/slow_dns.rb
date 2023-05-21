# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class SlowDNSServer < TestDNSResolver
  private

  def dns_response(query)
    domain = extract_domain(query)
    ip = Resolv.getaddress(domain)
    cname = ip =~ /[a-z]/

    # Valid response header
    response = "#{query[0, 2]}\x81\x00#{query[4, 2] * 2}\x00\x00\x00\x00".b

    # Append original question section
    response << query[12..-1].b

    # Use pointer to refer to domain name in question section
    response << "\xc0\x0c".b

    # Set response type accordingly
    response << (cname ? "\x00\x05".b : "\x00\x01".b)

    # Set response class (IN)
    response << "\x00\x01".b

    # TTL in seconds
    response << [120].pack("N").b

    # Calculate RDATA - we need its length in advance
    rdata = if cname
      ip.split(".").map { |a| a.length.chr + a }.join << "\x00"
    else
      # Append IP address as four 8 bit unsigned bytes
      ip.split(".").map(&:to_i).pack("C*")
    end

    # RDATA is 4 bytes
    response << [rdata.length].pack("n").b
    response << rdata.b
    response
  end
end
