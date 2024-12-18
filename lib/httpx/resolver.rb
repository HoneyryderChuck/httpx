# frozen_string_literal: true

require "resolv"
require "ipaddr"

module HTTPX
  module Resolver
    RESOLVE_TIMEOUT = [2, 3].freeze

    require "httpx/resolver/resolver"
    require "httpx/resolver/system"
    require "httpx/resolver/native"
    require "httpx/resolver/https"
    require "httpx/resolver/multi"

    @lookup_mutex = Thread::Mutex.new
    @lookups = Hash.new { |h, k| h[k] = [] }

    @identifier_mutex = Thread::Mutex.new
    @identifier = 1
    @system_resolver = Resolv::Hosts.new

    module_function

    def resolver_for(resolver_type)
      case resolver_type
      when :native then Native
      when :system then System
      when :https then HTTPS
      else
        return resolver_type if resolver_type.is_a?(Class) && resolver_type < Resolver

        raise Error, "unsupported resolver type (#{resolver_type})"
      end
    end

    def nolookup_resolve(hostname)
      ip_resolve(hostname) || cached_lookup(hostname) || system_resolve(hostname)
    end

    def ip_resolve(hostname)
      [IPAddr.new(hostname)]
    rescue ArgumentError
    end

    def system_resolve(hostname)
      ips = if in_ractor?
        Ractor.store_if_absent(:httpx_system_resolver) { Resolv::Hosts.new }
      else
        @system_resolver
      end.getaddresses(hostname)

      return if ips.empty?

      ips.map { |ip| IPAddr.new(ip) }
    rescue IOError
    end

    def cached_lookup(hostname)
      now = Utils.now
      lookup_synchronize do |lookups|
        lookup(hostname, lookups, now)
      end
    end

    def cached_lookup_set(hostname, family, entries)
      now = Utils.now
      entries.each do |entry|
        entry["TTL"] += now
      end
      lookup_synchronize do |lookups|
        case family
        when Socket::AF_INET6
          lookups[hostname].concat(entries)
        when Socket::AF_INET
          lookups[hostname].unshift(*entries)
        end
        entries.each do |entry|
          next unless entry["name"] != hostname

          case family
          when Socket::AF_INET6
            lookups[entry["name"]] << entry
          when Socket::AF_INET
            lookups[entry["name"]].unshift(entry)
          end
        end
      end
    end

    # do not use directly!
    def lookup(hostname, lookups, ttl)
      return unless lookups.key?(hostname)

      entries = lookups[hostname] = lookups[hostname].select do |address|
        address["TTL"] > ttl
      end

      ips = entries.flat_map do |address|
        if address.key?("alias")
          lookup(address["alias"], lookups, ttl)
        else
          IPAddr.new(address["data"])
        end
      end.compact

      ips unless ips.empty?
    end

    def generate_id
      if in_ractor?
        identifier = Ractor.store_if_absent(:httpx_resolver_identifier) { -1 }
        (Ractor.current[:httpx_resolver_identifier] = (identifier + 1) & 0xFFFF)
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

      return :dns_error, message.rcode if message.rcode != Resolv::DNS::RCode::NoError

      addresses = []

      message.each_answer do |question, _, value|
        case value
        when Resolv::DNS::Resource::IN::CNAME
          addresses << {
            "name" => question.to_s,
            "TTL" => value.ttl,
            "alias" => value.name.to_s,
          }
        when Resolv::DNS::Resource::IN::A,
             Resolv::DNS::Resource::IN::AAAA
          addresses << {
            "name" => question.to_s,
            "TTL" => value.ttl,
            "data" => value.address.to_s,
          }
        end
      end

      [:ok, addresses]
    end

    def lookup_synchronize
      if in_ractor?
        lookups = Ractor.store_if_absent(:httpx_resolver_lookups) { Hash.new { |h, k| h[k] = [] } }
        return yield(lookups)
      end

      @lookup_mutex.synchronize { yield(@lookups) }
    end

    def id_synchronize(&block)
      @identifier_mutex.synchronize(&block)
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
