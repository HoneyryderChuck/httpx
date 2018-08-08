# frozen_string_literal: true

module HTTPX
  module Resolver
    autoload :ResolverMixin, "httpx/resolver/resolver_mixin"
    autoload :System, "httpx/resolver/system"
    autoload :Native, "httpx/resolver/native"
    autoload :HTTPS, "httpx/resolver/https"

    extend Registry

    register :system, :System
    register :native, :Native
    register :https,  :HTTPS

    @lookup_mutex = Mutex.new
    @lookups = {}

    @identifier_mutex = Mutex.new
    @identifier = 1

    module_function

    def cached_lookup(hostname)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @lookup_mutex.synchronize do
        return unless @lookups.key?(hostname)
        @lookups[hostname] = @lookups[hostname].select do |address|
          address["TTL"] > now
        end
        ips = @lookups[hostname].map { |address| address["data"] }
        ips unless ips.empty?
      end
    end

    def cached_lookup_set(hostname, entries)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      entries.each do |entry|
        entry["TTL"] += now
      end
      @lookup_mutex.synchronize do
        @lookups[hostname] = entries
      end
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
        next unless value.respond_to?(:address)
        addresses << {
          "name" => question.to_s,
          "TTL"  => value.ttl,
          "data" => value.address.to_s,
        }
      end
      addresses
    end
  end
end

require "httpx/resolver/options"
