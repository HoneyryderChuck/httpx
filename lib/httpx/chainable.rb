# frozen_string_literal: true

module HTTPX
  # Session mixin, implements most of the APIs that the users call.
  # delegates to a default session when extended.
  module Chainable
    %w[head get post put delete trace options connect patch].each do |meth|
      class_eval(<<-MOD, __FILE__, __LINE__ + 1)
        def #{meth}(*uri, **options)                # def get(*uri, **options)
          request("#{meth.upcase}", uri, **options) #   request("GET", uri, **options)
        end                                         # end
      MOD
    end

    # delegates to the default session (see HTTPX::Session#request).
    def request(*args, **options)
      branch(default_options).request(*args, **options)
    end

    def accept(type)
      with(headers: { "accept" => String(type) })
    end

    # delegates to the default session (see HTTPX::Session#wrap).
    def wrap(&blk)
      branch(default_options).wrap(&blk)
    end

    # returns a new instance loaded with the +pl+ plugin and +options+.
    def plugin(pl, options = nil, &blk)
      klass = is_a?(S) ? self.class : Session
      klass = Class.new(klass)
      klass.instance_variable_set(:@default_options, klass.default_options.merge(default_options))
      klass.plugin(pl, options, &blk).new
    end

    # returns a new instance loaded with +options+.
    def with(options, &blk)
      branch(default_options.merge(options), &blk)
    end

    private

    # returns default instance of HTTPX::Options.
    def default_options
      @options || Session.default_options
    end

    # returns a default instance of HTTPX::Session.
    def branch(options, &blk)
      return self.class.new(options, &blk) if is_a?(S)

      Session.new(options, &blk)
    end

    def method_missing(meth, *args, **options, &blk)
      case meth
      when /\Awith_(.+)/

        option = Regexp.last_match(1)

        return super unless option

        with(option.to_sym => args.first || options)
      when /\Aon_(.+)/
        callback = Regexp.last_match(1)

        return super unless %w[
          connection_opened connection_closed
          request_error
          request_started request_body_chunk request_completed
          response_started response_body_chunk response_completed
        ].include?(callback)

        warn "DEPRECATION WARNING: calling `.#{meth}` on plain HTTPX sessions is deprecated. " \
             "Use HTTPX.plugin(:callbacks).#{meth} instead."

        plugin(:callbacks).__send__(meth, *args, **options, &blk)
      else
        super
      end
    end

    def respond_to_missing?(meth, *)
      case meth
      when /\Awith_(.+)/
        option = Regexp.last_match(1)

        default_options.respond_to?(option) || super
      when /\Aon_(.+)/
        callback = Regexp.last_match(1)

        %w[
          connection_opened connection_closed
          request_error
          request_started request_body_chunk request_completed
          response_started response_body_chunk response_completed
        ].include?(callback) || super
      else
        super
      end
    end
  end

  extend Chainable
end
