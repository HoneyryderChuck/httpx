# frozen_string_literal: true

module HTTPX
  module Chainable
    %w[head get post put delete trace options connect patch].each do |meth|
      class_eval(<<-MOD, __FILE__, __LINE__ + 1)
        def #{meth}(*uri, **options)                # def get(*uri, **options)
          request("#{meth.upcase}", uri, **options) #   request("GET", uri, **options)
        end                                         # end
      MOD
    end

    def request(*args, **options)
      branch(default_options).request(*args, **options)
    end

    def accept(type)
      with(headers: { "accept" => String(type) })
    end

    def wrap(&blk)
      branch(default_options).wrap(&blk)
    end

    def plugin(pl, options = nil, &blk)
      klass = is_a?(S) ? self.class : Session
      klass = Class.new(klass)
      klass.instance_variable_set(:@default_options, klass.default_options.merge(default_options))
      klass.plugin(pl, options, &blk).new
    end

    def with(options, &blk)
      branch(default_options.merge(options), &blk)
    end

    private

    def default_options
      @options || Session.default_options
    end

    def branch(options, &blk)
      return self.class.new(options, &blk) if is_a?(S)

      Session.new(options, &blk)
    end

    def method_missing(meth, *args, **options)
      return super unless meth =~ /\Awith_(.+)/

      option = Regexp.last_match(1)

      return super unless option

      with(option.to_sym => args.first || options)
    end

    def respond_to_missing?(meth, *)
      return super unless meth =~ /\Awith_(.+)/

      option = Regexp.last_match(1)

      default_options.respond_to?(option) || super
    end
  end
end
