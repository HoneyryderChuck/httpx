# frozen_string_literal: true

module HTTPX::Channel
  module_function

  def by(uri, options)
    case uri.scheme
    when "http"
      TCP.new(uri, options)
    when "https"
      SSL.new(uri, options)
    else
      raise Error, "#{uri.scheme}: unrecognized channel"
    end
  end
end

require "httpx/channel/http2"
require "httpx/channel/http1"
require "httpx/channel/tcp"
require "httpx/channel/ssl"
