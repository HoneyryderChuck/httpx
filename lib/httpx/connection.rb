# frozen_string_literal: true

require "httpx/selector"
require "httpx/channel"

module HTTPX
  class Connection
    def initialize(options)
      @options = Options.new(options)
      @timeout = options.timeout
      @selector = Selector.new
      @channels = []
    end

    def running?
      !@channels.empty?
    end

    def next_tick(timeout: @timeout.timeout)
      @selector.select(timeout) do |monitor|
        if (channel = monitor.value)
          consume(channel)
        end
        monitor.interests = channel.interests
      end
    end

    def close(channel = nil)
      if channel
        channel.close
      else
        @channels.each(&:close)
        next_tick until @selector.empty?
      end
    end

    def build_channel(uri, **options)
      channel = Channel.by(uri, @options.merge(options))
      register_channel(channel)
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

    def register_channel(channel)
      monitor = @selector.register(channel, :w)
      monitor.value = channel
      channel.on(:close) do
        @channels.delete(channel)
        @selector.deregister(channel)
      end
      @channels << channel
    end

    def consume(channel)
      ch = catch(:close) { channel.call }
      close(ch) if ch
    end
  end
end
