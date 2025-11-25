# frozen_string_literal: true

require "resolv"
require_relative "test"

# from https://gist.github.com/peterc/1425383

class DNSServFailOnce < TestDNSResolver
  attr_reader :failed

  def initialize(*, **)
    super
    @failed = false
  end

  private

  def dns_response(query)
    return super if @failed

    @failed = true

    response_header(query, 2).force_encoding(Encoding::BINARY) <<
      question_section(query).force_encoding(Encoding::BINARY)
  end
end
