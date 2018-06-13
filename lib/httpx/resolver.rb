# frozen_string_literal: true

module HTTPX
  module Resolver
    autoload :System, "httpx/resolver/system"
    autoload :Native, "httpx/resolver/native"

    extend Registry

    register :system, :System
    register :native, :Native
  end
end
