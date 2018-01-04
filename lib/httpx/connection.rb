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
      @responses = {}
    end

    def running?
      !@channels.empty?
    end

    def next_tick(timeout: @timeout.timeout)
      @selector.select(timeout) do |monitor|
        if channel = monitor.value
          consume(channel)
        end
      end
    end

    def close(channel = nil)
      if channel
        if channel.close
          @channels.delete(channel)
          @selector.deregister(channel)
        end
      else
        while ch = @channels.shift
          ch.close(true)
          @selector.deregister(ch)
        end 
      end
    end

    def response(request)
      response = @responses.delete(request)
      if response.is_a?(ErrorResponse) && response.retryable?
        send(request, retries: response.retries - 1)
        return 
      end 
      response
    end

    def build_channel(uri)
      channel = Channel.by(uri, @options, &method(:on_response))
      register_channel(channel)
      channel
    end

    # opens a channel to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few channels as possible.
    #
    def find_channel(uri)
      return @channels.find do |channel|
        channel.match?(uri)
      end
    end

    private

    def on_response(request, response)
      @responses[request] = response
    end

    def register_channel(channel)
      monitor = @selector.register(channel, :rw)
      monitor.value = channel
      @channels << channel
    end

    def consume(channel)
      ch = catch(:close) { channel.call }
      close(ch) if ch
    end
  end
end
