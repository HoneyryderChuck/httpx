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

    # :nocov:
    def timeout(**args)
      warn ":#{__method__} is deprecated, use :with_timeout instead"
      branch(default_options.with(timeout: args))
    end

    def headers(headers)
      warn ":#{__method__} is deprecated, use :with_headers instead"
      branch(default_options.with(headers: headers))
    end
    # :nocov:

    def accept(type)
      with(headers: { "accept" => String(type) })
    end

    def wrap(&blk)
      branch(default_options).wrap(&blk)
    end

    def plugin(*args, **opts)
      klass = is_a?(Session) ? self.class : Session
      klass = Class.new(klass)
      klass.instance_variable_set(:@default_options, klass.default_options.merge(default_options))
      klass.plugin(*args, **opts).new
    end

    # deprecated
    def plugins(*args, **opts)
      klass = is_a?(Session) ? self.class : Session
      klass = Class.new(klass)
      klass.instance_variable_set(:@default_options, klass.default_options.merge(default_options))
      klass.plugins(*args, **opts).new
    end

    def with(options, &blk)
      branch(default_options.merge(options), &blk)
    end

    private

    def default_options
      @options || Options.new
    end

    # :nodoc:
    def branch(options, &blk)
      return self.class.new(options, &blk) if is_a?(Session)

      Session.new(options, &blk)
    end

    def method_missing(meth, *args, **options)
      if meth =~ /\Awith_(.+)/
        option = Regexp.last_match(1).to_sym
        with(option => (args.first || options))
      else
        super
      end
    end

    def respond_to_missing?(meth, *args)
      default_options.respond_to?(meth, *args) || super
    end
  end
end
