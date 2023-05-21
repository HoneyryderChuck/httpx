# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSSameRelativeName < TestDNSResolver
  private

  def question_section(query)
    domain = extract_domain(query)
    section = [domain.size].pack("C") << domain.b << query[-5..-1]

    # Use pointer to refer to domain name in question section
    section << "\xc0\x0c".b

    section
  end
end
