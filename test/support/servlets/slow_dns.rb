# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class SlowDNSServer < TestDNSResolver
  def initialize(timeout, *args, hostname: nil, als: nil)
    @timeout = timeout
    @hostname = hostname
    @alias = als
    super(*args)
  end

  private

  def dns_response(query)
    if @alias
      domain = extract_domain(query)
      sleep(@timeout) if domain == @alias
    else
      sleep(@timeout)
    end
    super
  end

  def resolve(domain)
    if domain == "#{@hostname}."
      @alias
    else
      super
    end
  end
end
