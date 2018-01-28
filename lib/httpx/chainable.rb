# frozen_string_literal: true

module HTTPX
  module Chainable
    %i[head get post put delete trace options connect patch].each do |meth|
      define_method meth do |*uri, **options|
        request(meth, *uri, **options)
      end
    end

    def request(verb, uri, **options)
      branch(**options).request(verb, uri)
    end

    def timeout(**args)
      branch(timeout: args)
    end

    def headers(headers)
      branch(default_options.with_headers(headers))
    end

    def accept(type)
      headers("accept" => String(type)) 
    end

    def plugin(*plugins)
      Class.new(Client).plugins(plugins).new
    end
    alias :plugins :plugin

    def with(options)
      branch(default_options.merge(options))
    end

    private

    def default_options
      @options || Options.new
    end

    # :nodoc:
    def branch(options)
      return self.class.new(options) if self.is_a?(Client)
      Client.new(options)
    end
  end
end

