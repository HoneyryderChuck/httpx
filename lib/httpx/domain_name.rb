# frozen_string_literal: true

#
# domain_name.rb - Domain Name manipulation library for Ruby
#
# Copyright (C) 2011-2017 Akinori MUSHA, All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

require "ipaddr"

module HTTPX
  # Represents a domain name ready for extracting its registered domain
  # and TLD.
  class DomainName
    include Comparable

    # The full host name normalized, ASCII-ized and downcased using the
    # Unicode NFC rules and the Punycode algorithm.  If initialized with
    # an IP address, the string representation of the IP address
    # suitable for opening a connection to.
    attr_reader :hostname

    # The Unicode representation of the #hostname property.
    #
    # :attr_reader: hostname_idn

    # The least "universally original" domain part of this domain name.
    # For example, "example.co.uk" for "www.sub.example.co.uk".  This
    # may be nil if the hostname does not have one, like when it is an
    # IP address, an effective TLD or higher itself, or of a
    # non-canonical domain.
    attr_reader :domain

    class << self
      def new(domain)
        return domain if domain.is_a?(self)

        super(domain)
      end

      # Normalizes a _domain_ using the Punycode algorithm as necessary.
      # The result will be a downcased, ASCII-only string.
      def normalize(domain)
        domain = domain.chomp(DOT).unicode_normalize(:nfc) unless domain.ascii_only?
        Punycode.encode_hostname(domain).downcase
      end
    end

    # Parses _hostname_ into a DomainName object.  An IP address is also
    # accepted.  An IPv6 address may be enclosed in square brackets.
    def initialize(hostname)
      hostname = String(hostname)

      raise ArgumentError, "domain name must not start with a dot: #{hostname}" if hostname.start_with?(".")

      begin
        @ipaddr = IPAddr.new(hostname)
        @hostname = @ipaddr.to_s
        return
      rescue IPAddr::Error
        nil
      end

      @hostname = DomainName.normalize(hostname)
      tld = if (last_dot = @hostname.rindex("."))
        @hostname[(last_dot + 1)..-1]
      else
        @hostname
      end

      # unknown/local TLD
      @domain = if last_dot
        # fallback - accept cookies down to second level
        # cf. http://www.dkim-reputation.org/regdom-libs/
        if (penultimate_dot = @hostname.rindex(".", last_dot - 1))
          @hostname[(penultimate_dot + 1)..-1]
        else
          @hostname
        end
      else
        # no domain part - must be a local hostname
        tld
      end
    end

    # Checks if the server represented by this domain is qualified to
    # send and receive cookies with a domain attribute value of
    # _domain_.  A true value given as the second argument represents
    # cookies without a domain attribute value, in which case only
    # hostname equality is checked.
    def cookie_domain?(domain, host_only = false)
      # RFC 6265 #5.3
      # When the user agent "receives a cookie":
      return self == @domain if host_only

      domain = DomainName.new(domain)

      # RFC 6265 #5.1.3
      # Do not perform subdomain matching against IP addresses.
      @hostname == domain.hostname if @ipaddr

      # RFC 6265 #4.1.1
      # Domain-value must be a subdomain.
      @domain && self <= domain && domain <= @domain
    end

    def <=>(other)
      other = DomainName.new(other)
      othername = other.hostname
      if othername == @hostname
        0
      elsif @hostname.end_with?(othername) && @hostname[-othername.size - 1, 1] == "."
        # The other is higher
        -1
      else
        # The other is lower
        1
      end
    end
  end
end
