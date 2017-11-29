# frozen_string_literal: true

module HTTPX::Channel
  module_function

  def by(uri, options, &blk)
    case uri.scheme
    when "http"
      TCP.new(uri, options, &blk)
    when "https"
      SSL.new(uri, options, &blk)
    else
      raise Error, "#{uri.scheme}: unrecognized channel"
    end
  end
end

require "httpx/channel/http2"
require "httpx/channel/http1"
require "httpx/channel/tcp"
require "httpx/channel/ssl"
