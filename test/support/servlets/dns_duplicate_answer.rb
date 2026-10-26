# frozen_string_literal: true

require "resolv"
require_relative "test"

# replies to every query twice, to simulate the use case where a query times out, is retried, and
# both the original and the retried query get answered.
class DNSDuplicateAnswer < TestDNSResolver
  def initialize(addresses, *args, **kwargs)
    @addresses = addresses
    super(*args, **kwargs)
  end

  def start
    Socket.udp_server_loop(@port) do |query, src|
      @queries += 1
      answer = dns_response(query)

      2.times do
        src.reply(answer)
        @answers += 1
      end
    end
  end

  private

  def resolve(domain, *)
    Array(@addresses.fetch(domain.delete_suffix(".")) { raise Resolv::ResolvError })
  end
end
