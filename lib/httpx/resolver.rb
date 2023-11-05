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

    @lookup_mutex = Mutex.new
    @lookups = Hash.new { |h, k| h[k] = [] }

    @identifier_mutex = Mutex.new
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
      ips = @system_resolver.getaddresses(hostname)
      return if ips.empty?

      ips.map { |ip| IPAddr.new(ip) }
    rescue IOError
    end

    def cached_lookup(hostname)
      now = Utils.now
      @lookup_mutex.synchronize do
        lookup(hostname, now)
      end
    end

    def cached_lookup_set(hostname, family, entries)
      now = Utils.now
      entries.each do |entry|
        entry["TTL"] += now
      end
      @lookup_mutex.synchronize do
        case family
        when Socket::AF_INET6
          @lookups[hostname].concat(entries)
        when Socket::AF_INET
          @lookups[hostname].unshift(*entries)
        end
        entries.each do |entry|
          next unless entry["name"] != hostname

          case family
          when Socket::AF_INET6
            @lookups[entry["name"]] << entry
          when Socket::AF_INET
            @lookups[entry["name"]].unshift(entry)
          end
        end
      end
    end

    # do not use directly!
    def lookup(hostname, ttl)
      return unless @lookups.key?(hostname)

      entries = @lookups[hostname] = @lookups[hostname].select do |address|
        address["TTL"] > ttl
      end

      ips = entries.flat_map do |address|
        if address.key?("alias")
          lookup(address["alias"], ttl)
        else
          IPAddr.new(address["data"])
        end
      end.compact

      ips unless ips.empty?
    end

    def generate_id
      @identifier_mutex.synchronize { @identifier = (@identifier + 1) & 0xFFFF }
    end

    def encode_dns_query(hostname, type: Resolv::DNS::Resource::IN::A, message_id: generate_id)
      Resolv::DNS::Message.new.tap do |query|
        query.id = message_id
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
  end
end
