# frozen_string_literal: true

require "socket"
require "resolv"

module HTTPX
  module Resolver
    extend self

    RESOLVE_TIMEOUT = [2, 3].freeze
    MAX_CACHE_SIZE = 512

    require "httpx/resolver/entry"
    require "httpx/resolver/resolver"
    require "httpx/resolver/system"
    require "httpx/resolver/native"
    require "httpx/resolver/https"
    require "httpx/resolver/multi"

    @lookup_mutex = Thread::Mutex.new
    @hostnames = []
    @lookups = Hash.new { |h, k| h[k] = [] }

    @identifier_mutex = Thread::Mutex.new
    @identifier = 1
    @hosts_resolver = Resolv::Hosts.new

    def supported_ip_families
      if in_ractor?
        Ractor.store_if_absent(:httpx_supported_ip_families) { find_supported_ip_families }
      else
        @supported_ip_families ||= find_supported_ip_families
      end
    end

    def resolver_for(resolver_type, options)
      case resolver_type
      when Symbol
        meth = :"resolver_#{resolver_type}_class"

        return options.__send__(meth) if options.respond_to?(meth)
      when Class
        return resolver_type if resolver_type < Resolver
      end

      raise Error, "unsupported resolver type (#{resolver_type})"
    end

    def nolookup_resolve(hostname)
      ip_resolve(hostname) || cached_lookup(hostname) || hosts_resolve(hostname)
    end

    # tries to convert +hostname+ into an IPAddr, returns <tt>nil</tt> otherwise.
    def ip_resolve(hostname)
      [Entry.new(hostname)]
    rescue ArgumentError
    end

    # matches +hostname+ to entries in the hosts file, returns <tt>nil</nil> if none is
    # found, or there is no hosts file.
    def hosts_resolve(hostname)
      ips = if in_ractor?
        Ractor.store_if_absent(:httpx_hosts_resolver) { Resolv::Hosts.new }
      else
        @hosts_resolver
      end.getaddresses(hostname)

      return if ips.empty?

      ips.map { |ip| Entry.new(ip) }
    rescue IOError
    end

    def cached_lookup(hostname)
      now = Utils.now
      lookup_synchronize do |lookups, hostnames|
        lookup(hostname, lookups, hostnames, now)
      end
    end

    def cached_lookup_set(hostname, family, entries)
      lookup_synchronize do |lookups, hostnames|
        # lru cleanup
        while lookups.size >= MAX_CACHE_SIZE
          hs = hostnames.shift
          lookups.delete(hs)
        end
        hostnames << hostname

        case family
        when Socket::AF_INET6
          lookups[hostname].concat(entries)
        when Socket::AF_INET
          lookups[hostname].unshift(*entries)
        end
        entries.each do |entry|
          name = entry["name"]
          next unless name != hostname

          case family
          when Socket::AF_INET6
            lookups[name] << entry
          when Socket::AF_INET
            lookups[name].unshift(entry)
          end
        end
      end
    end

    def cached_lookup_evict(hostname, ip)
      ip = ip.to_s

      lookup_synchronize do |lookups, hostnames|
        entries = lookups[hostname]

        return unless entries

        entries.delete_if { |entry| entry["data"] == ip }

        if entries.empty?
          lookups.delete(hostname)
          hostnames.delete(hostname)
        end
      end
    end

    # do not use directly!
    def lookup(hostname, lookups, hostnames, ttl)
      return unless lookups.key?(hostname)

      entries = lookups[hostname]

      entries.delete_if do |address|
        address["TTL"] < ttl
      end

      if entries.empty?
        lookups.delete(hostname)
        hostnames.delete(hostname)
      end

      ips = entries.flat_map do |address|
        if (als = address["alias"])
          lookup(als, lookups, hostnames, ttl)
        else
          Entry.new(address["data"], address["TTL"])
        end
      end.compact

      ips unless ips.empty?
    end

    def generate_id
      if in_ractor?
        identifier = Ractor.store_if_absent(:httpx_resolver_identifier) { -1 }
        Ractor.current[:httpx_resolver_identifier] = (identifier + 1) & 0xFFFF
      else
        id_synchronize { @identifier = (@identifier + 1) & 0xFFFF }
      end
    end

    def encode_dns_query(hostname, type: Resolv::DNS::Resource::IN::A, message_id: generate_id)
      Resolv::DNS::Message.new(message_id).tap do |query|
        query.rd = 1
        query.add_question(hostname, type)
      end.encode
    end

    def decode_dns_answer(payload)
      begin
        message = Resolv::DNS::Message.decode(payload)
      rescue Resolv::DNS::DecodeError => e
        return :decode_error, e
      end

      # no domain was found
      return :no_domain_found if message.rcode == Resolv::DNS::RCode::NXDomain

      return :message_truncated if message.tc == 1

      if message.rcode != Resolv::DNS::RCode::NoError
        case message.rcode
        when Resolv::DNS::RCode::ServFail
          return :retriable_error, message.rcode
        else
          return :dns_error, message.rcode
        end
      end

      addresses = []

      now = Utils.now
      message.each_answer do |question, _, value|
        case value
        when Resolv::DNS::Resource::IN::CNAME
          addresses << {
            "name" => question.to_s,
            "TTL" => (now + value.ttl),
            "alias" => value.name.to_s,
          }
        when Resolv::DNS::Resource::IN::A,
             Resolv::DNS::Resource::IN::AAAA
          addresses << {
            "name" => question.to_s,
            "TTL" => (now + value.ttl),
            "data" => value.address.to_s,
          }
        end
      end

      [:ok, addresses]
    end

    private

    def lookup_synchronize
      if in_ractor?
        lookups = Ractor.store_if_absent(:httpx_resolver_lookups) { Hash.new { |h, k| h[k] = [] } }
        hostnames = Ractor.store_if_absent(:httpx_resolver_hostnames) { [] }
        return yield(lookups, hostnames)
      end

      @lookup_mutex.synchronize { yield(@lookups, @hostnames) }
    end

    def id_synchronize(&block)
      @identifier_mutex.synchronize(&block)
    end

    def find_supported_ip_families
      list = Socket.ip_address_list

      begin
        if list.any? { |a| a.ipv6? && !a.ipv6_loopback? && !a.ipv6_linklocal? }
          [Socket::AF_INET6, Socket::AF_INET]
        else
          [Socket::AF_INET]
        end
      rescue NotImplementedError
        [Socket::AF_INET]
      end.freeze
    end

    if defined?(Ractor) &&
       # no ractor support for 3.0
       RUBY_VERSION >= "3.1.0"

      def in_ractor?
        Ractor.main != Ractor.current
      end
    else
      def in_ractor?
        false
      end
    end
  end
end
