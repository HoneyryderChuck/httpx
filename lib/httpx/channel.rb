# frozen_string_literal: true

module HTTPX::Channel
  module_function

  def by(uri)
    case uri.scheme
    when "http"
      TCP.new(uri)
    when "https"
      TLS.new(uri)
    else
      raise "#{uri.scheme}: unrecognized channel"
    end
  end
end

require "httpx/channel/http2"
require "httpx/channel/tcp"
