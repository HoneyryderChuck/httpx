# frozen_string_literal: true

require "httpx/selector"
require "httpx/channel"
require "httpx/resolver"

module HTTPX
  class Connection
    def initialize(options)
      @options = Options.new(options)
      @timeout = options.timeout
      @resolver = Resolver.new(@options)
      @selector = Selector.new
      @channels = []
      @resolver.on(:resolve, &method(:on_resolver_channel))
      @resolver.on(:close, &method(:on_resolver_close))
    end

    def running?
      !@channels.empty?
    end

    def next_tick
      timeout = @timeout.timeout
      @selector.select(timeout) do |monitor|
        if (channel = monitor.value)
          channel.call
        end
        monitor.interests = channel.interests
      end
    rescue TimeoutError,
           Errno::ECONNRESET,
           Errno::ECONNABORTED,
           Errno::EPIPE => ex
      @channels.each do |ch|
        ch.emit(:error, ex)
      end
    end

    def close
      @channels.each(&:close)
      next_tick until @channels.empty?
    end

    def build_channel(uri, **options)
      channel = Channel.by(uri, @options.merge(options))
      resolve_channel(channel)
      channel
    end

    # opens a channel to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few channels as possible.
    #
    def find_channel(uri)
      @channels.find do |channel|
        channel.match?(uri)
      end
    end

    private

    def resolve_channel(channel)
      @resolver << channel
      return if @resolver.empty?
      @resolver_monitor ||= begin
        monitor = @selector.register(@resolver, :w)
        monitor.value = @resolver
        monitor
      end
    end

    def on_resolver_channel(channel)
      register_channel(channel)
    end

    def on_resolver_close
      @timeout.next_timeout # disconnect resolve timeout
      @selector.deregister(@resolver)
      @resolver_monitor = nil
      @resolver.close
    end

    def register_channel(channel)
      monitor = @selector.register(channel, :w)
      monitor.value = channel
      channel.on(:close) do
        @channels.delete(channel)
        @selector.deregister(channel)
      end
      @channels << channel
    end
  end
end
