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

    def send(request, **args)
      channel = bind(request.uri)
      raise Error, "no channel available" unless channel

      channel.send(request, **args)
    end
    alias :<< :send

    def next_tick(timeout: @timeout.timeout)
      @selector.select(timeout) do |monitor|
        if task = monitor.value
          consume(task)
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

    private

    # opens a channel to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few channels as possible.
    #
    def bind(uri)
      uri = URI(uri)
      return @channels.find do |channel|
        channel.match?(uri)
      end || begin
        build_channel(uri)
      end
    end

    def build_channel(uri)
      channel = Channel.by(uri, @options) do |request, response|
        @responses[request] = response
      end
      register_channel(channel)
      channel
    end

    def register_channel(channel)
      monitor = @selector.register(channel, :rw)
      monitor.value = channel
      @channels << channel
    end

    def consume(task)
      channel = catch(:close) { task.call }
      close(channel) if channel 
    end
  end
end
