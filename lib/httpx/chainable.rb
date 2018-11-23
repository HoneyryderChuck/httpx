# frozen_string_literal: true

module HTTPX
  module Chainable
    %i[head get post put delete trace options connect patch].each do |meth|
      define_method meth do |*uri, **options|
        request(meth, uri, **options)
      end
    end

    def request(verb, uri, **options)
      branch(default_options).request(verb, uri, **options)
    end

    def timeout(**args)
      branch(default_options.with_timeout(args))
    end

    def headers(headers)
      branch(default_options.with_headers(headers))
    end

    def accept(type)
      headers("accept" => String(type))
    end

    def wrap(&blk)
      branch(default_options).wrap(&blk)
    end

    def plugin(*plugins)
      klass = is_a?(Client) ? self.class : Client
      klass = Class.new(klass)
      klass.instance_variable_set(:@default_options, klass.default_options.merge(default_options))
      klass.plugins(plugins).new
    end
    alias_method :plugins, :plugin

    def with(options, &blk)
      branch(default_options.merge(options), &blk)
    end

    private

    def default_options
      @options || Options.new
    end

    # :nodoc:
    def branch(options, &blk)
      return self.class.new(options, &blk) if is_a?(Client)
      Client.new(options, &blk)
    end
  end
end
