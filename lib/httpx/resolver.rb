# frozen_string_literal: true

require "socket"
require "resolv"

module HTTPX
  module Resolver
    extend self

    RESOLVE_TIMEOUT = [2, 3].freeze
    require "httpx/resolver/entry"
    require "httpx/resolver/cache"
    require "httpx/resolver/resolver"
    require "httpx/resolver/system"
    require "httpx/resolver/native"
    require "httpx/resolver/https"
    require "httpx/resolver/multi"

    @identifier_mutex = Thread::Mutex.new
    @identifier = 1

    def supported_ip_families
      if Utils.in_ractor?
        Ractor.store_if_absent(:httpx_supported_ip_families) { find_supported_ip_families }
      else
        @supported_ip_families ||= find_supported_ip_families
      end
    end

    def generate_id
      if Utils.in_ractor?
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
  end
end
