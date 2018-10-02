# frozen_string_literal: true

require "httpx/selector"
require "httpx/channel"
require "httpx/resolver"

module HTTPX
  class Connection
    def initialize(options)
      @options = Options.new(options)
      @timeout = options.timeout
      resolver_type = @options.resolver_class
      resolver_type = Resolver.registry(resolver_type) if resolver_type.is_a?(Symbol)
      @selector = Selector.new
      @channels = []
      @resolver = resolver_type.new(self, @options)
      @resolver.on(:resolve, &method(:on_resolver_channel))
      @resolver.on(:error, &method(:on_resolver_error))
      @resolver.on(:close, &method(:on_resolver_close))
    end

    def running?
      !@channels.empty?
    end

    def next_tick
      catch(:jump_tick) do
        @selector.select(next_timeout) do |monitor|
          if (channel = monitor.value)
            channel.call
          end
          monitor.interests = channel.interests
        end
      end
    rescue TimeoutError => timeout_error
      @channels.each do |ch|
        error = timeout_error
        error = error.to_connection_error if ch.connecting?
        ch.emit(:error, error)
      end
    rescue Errno::ECONNRESET,
           Errno::ECONNABORTED,
           Errno::EPIPE => ex
      @channels.each do |ch|
        ch.emit(:error, ex)
      end
    end

    def close
      @resolver.close unless @resolver.closed?
      @channels.each(&:close)
      next_tick until @channels.empty?
    end

    def build_channel(uri, **options)
      channel = Channel.by(uri, @options.merge(options))
      resolve_channel(channel)
      channel.once(:unreachable) do
        @resolver.uncache(channel)
        resolve_channel(channel)
      end
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
      @channels << channel unless @channels.include?(channel)
      @resolver << channel
      return if @resolver.empty?
      @_resolver_monitor ||= begin # rubocop:disable Naming/MemoizedInstanceVariableName
        monitor = @selector.register(@resolver, :w)
        monitor.value = @resolver
        monitor
      end
    end

    def on_resolver_channel(channel, addresses)
      found_channel = @channels.find do |ch|
        ch != channel && ch.mergeable?(addresses)
      end
      return register_channel(channel) unless found_channel
      if found_channel.state == :open
        coalesce_channels(found_channel, channel)
      else
        found_channel.once(:open) do
          coalesce_channels(found_channel, channel)
        end
      end
    end

    def on_resolver_error(ch, error)
      ch.emit(:error, error)
      # must remove channel by hand, hasn't been started yet
      unregister_channel(ch)
    end

    def on_resolver_close
      @selector.deregister(@resolver)
      @_resolver_monitor = nil
      @resolver.close unless @resolver.closed?
    end

    def register_channel(channel)
      monitor = @selector.register(channel, :w)
      monitor.value = channel
      channel.on(:close) do
        unregister_channel(channel)
      end
    end

    def unregister_channel(channel)
      @channels.delete(channel)
      @selector.deregister(channel)
    end

    def coalesce_channels(ch1, ch2)
      if ch1.coalescable?(ch2)
        ch1.merge(ch2)
        @channels.delete(ch2)
      else
        register_channel(ch2)
      end
    end

    def next_timeout
      timeout = @timeout.timeout # force log time
      return (@resolver.timeout || timeout) unless @resolver.closed?
      timeout
    end
  end
end
