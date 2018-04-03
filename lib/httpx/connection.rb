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

    def next_tick
      timeout = @timeout.timeout
      @selector.select(timeout) do |monitor|
        if (channel = monitor.value)
          channel.call
        end
        monitor.interests = channel.interests
      end
    rescue TimeoutError => ex
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
  end
end
