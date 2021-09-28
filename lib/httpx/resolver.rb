# frozen_string_literal: true

require "resolv"

module HTTPX
  module Resolver
    extend Registry

    RESOLVE_TIMEOUT = 5

    require "httpx/resolver/resolver"
    require "httpx/resolver/system"
    require "httpx/resolver/native"
    require "httpx/resolver/https"

    register :system, System
    register :native, Native
    register :https,  HTTPS

    @lookup_mutex = Mutex.new
    @lookups = Hash.new { |h, k| h[k] = [] }

    @identifier_mutex = Mutex.new
    @identifier = 1

    module_function

    def cached_lookup(hostname)
      now = Utils.now
      @lookup_mutex.synchronize do
        lookup(hostname, now)
      end
    end

    def cached_lookup_set(hostname, entries)
      now = Utils.now
      entries.each do |entry|
        entry["TTL"] += now
      end
      @lookup_mutex.synchronize do
        @lookups[hostname] += entries
        entries.each do |entry|
          @lookups[entry["name"]] << entry if entry["name"] != hostname
        end
      end
    end

    def uncache(hostname)
      @lookup_mutex.synchronize do
        @lookups.delete(hostname)
      end
    end

    # do not use directly!
    def lookup(hostname, ttl)
      return unless @lookups.key?(hostname)

      @lookups[hostname] = @lookups[hostname].select do |address|
        address["TTL"] > ttl
      end
      ips = @lookups[hostname].flat_map do |address|
        if address.key?("alias")
          lookup(address["alias"], ttl)
        else
          address["data"]
        end
      end
      ips unless ips.empty?
    end

    def generate_id
      @identifier_mutex.synchronize { @identifier = (@identifier + 1) & 0xFFFF }
    end

    def encode_dns_query(hostname, type: Resolv::DNS::Resource::IN::A)
      Resolv::DNS::Message.new.tap do |query|
        query.id = generate_id
        query.rd = 1
        query.add_question(hostname, type)
      end.encode
    end

    def decode_dns_answer(payload)
      message = Resolv::DNS::Message.decode(payload)
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
      addresses
    end
  end
end
