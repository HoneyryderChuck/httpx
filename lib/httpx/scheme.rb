# frozen_string_literal: true

module HTTPX::Scheme
  module_function

  def by(uri)
    case uri.scheme
    when "http"
      HTTP.new(uri)
    when "https"
      HTTPS.new(uri)
    else
      raise "unrecognized Scheme"
    end
  end
end

require "httpx/scheme/http"
