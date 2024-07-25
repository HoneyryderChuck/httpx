# frozen_string_literal: true

module HTTPX
  class ServerSideRequestForgeryError < Error; end

  module Plugins
    #
    # This plugin adds support for preventing Server-Side Request Forgery attacks.
    #
    # https://gitlab.com/os85/httpx/wikis/Server-Side-Request-Forgery-Filter
    #
    module SsrfFilter
      module IPAddrExtensions
        refine IPAddr do
          def prefixlen
            mask_addr = @mask_addr
            raise "Invalid mask" if mask_addr.zero?

            mask_addr >>= 1 while (mask_addr & 0x1).zero?

            length = 0
            while mask_addr & 0x1 == 0x1
              length += 1
              mask_addr >>= 1
            end

            length
          end
        end
      end

      using IPAddrExtensions

      # https://en.wikipedia.org/wiki/Reserved_IP_addresses
      IPV4_BLACKLIST = [
        IPAddr.new("0.0.0.0/8"), # Current network (only valid as source address)
        IPAddr.new("10.0.0.0/8"), # Private network
        IPAddr.new("100.64.0.0/10"), # Shared Address Space
        IPAddr.new("127.0.0.0/8"), # Loopback
        IPAddr.new("169.254.0.0/16"), # Link-local
        IPAddr.new("172.16.0.0/12"), # Private network
        IPAddr.new("192.0.0.0/24"), # IETF Protocol Assignments
        IPAddr.new("192.0.2.0/24"), # TEST-NET-1, documentation and examples
        IPAddr.new("192.88.99.0/24"), # IPv6 to IPv4 relay (includes 2002::/16)
        IPAddr.new("192.168.0.0/16"), # Private network
        IPAddr.new("198.18.0.0/15"), # Network benchmark tests
        IPAddr.new("198.51.100.0/24"), # TEST-NET-2, documentation and examples
        IPAddr.new("203.0.113.0/24"), # TEST-NET-3, documentation and examples
        IPAddr.new("224.0.0.0/4"), # IP multicast (former Class D network)
        IPAddr.new("240.0.0.0/4"), # Reserved (former Class E network)
        IPAddr.new("255.255.255.255"), # Broadcast
      ].freeze

      IPV6_BLACKLIST = ([
        IPAddr.new("::1/128"), # Loopback
        IPAddr.new("64:ff9b::/96"), # IPv4/IPv6 translation (RFC 6052)
        IPAddr.new("100::/64"), # Discard prefix (RFC 6666)
        IPAddr.new("2001::/32"), # Teredo tunneling
        IPAddr.new("2001:10::/28"), # Deprecated (previously ORCHID)
        IPAddr.new("2001:20::/28"), # ORCHIDv2
        IPAddr.new("2001:db8::/32"), # Addresses used in documentation and example source code
        IPAddr.new("2002::/16"), # 6to4
        IPAddr.new("fc00::/7"), # Unique local address
        IPAddr.new("fe80::/10"), # Link-local address
        IPAddr.new("ff00::/8"), # Multicast
      ] + IPV4_BLACKLIST.flat_map do |ipaddr|
        prefixlen = ipaddr.prefixlen

        ipv4_compatible = ipaddr.ipv4_compat.mask(96 + prefixlen)
        ipv4_mapped = ipaddr.ipv4_mapped.mask(80 + prefixlen)

        [ipv4_compatible, ipv4_mapped]
      end).freeze

      class << self
        def extra_options(options)
          options.merge(allowed_schemes: %w[https http])
        end

        def unsafe_ip_address?(ipaddr)
          range = ipaddr.to_range
          return true if range.first != range.last

          return IPV6_BLACKLIST.any? { |r| r.include?(ipaddr) } if ipaddr.ipv6?

          IPV4_BLACKLIST.any? { |r| r.include?(ipaddr) } # then it's IPv4
        end
      end

      # adds support for the following options:
      #
      # :allowed_schemes :: list of URI schemes allowed (defaults to <tt>["https", "http"]</tt>)
      module OptionsMethods
        def option_allowed_schemes(value)
          Array(value)
        end
      end

      module InstanceMethods
        def send_requests(*requests)
          responses = requests.map do |request|
            next if @options.allowed_schemes.include?(request.uri.scheme)

            error = ServerSideRequestForgeryError.new("#{request.uri} URI scheme not allowed")
            error.set_backtrace(caller)
            response = ErrorResponse.new(request, error)
            request.emit(:response, response)
            response
          end
          allowed_requests = requests.select { |req| responses[requests.index(req)].nil? }
          allowed_responses = super(*allowed_requests)
          allowed_responses.each_with_index do |res, idx|
            req = allowed_requests[idx]
            responses[requests.index(req)] = res
          end

          responses
        end
      end

      module ConnectionMethods
        def initialize(*)
          begin
            super
          rescue ServerSideRequestForgeryError => e
            # may raise when IPs are passed as options via :addresses
            throw(:resolve_error, e)
          end
        end

        def addresses=(addrs)
          addrs = addrs.map { |addr| addr.is_a?(IPAddr) ? addr : IPAddr.new(addr) }

          addrs.reject!(&SsrfFilter.method(:unsafe_ip_address?))

          raise ServerSideRequestForgeryError, "#{@origin.host} has no public IP addresses" if addrs.empty?

          super
        end
      end
    end

    register_plugin :ssrf_filter, SsrfFilter
  end
end
