# frozen_string_literal: true

require "socket"
require "timeout"

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
        channel.close
        if channel.closed?
          @channels.delete(channel)
          @selector.deregister(channel)
        end
      else
        while ch = @channels.shift
          ch.close
          @selector.deregister(ch)
        end 
      end
    end

    def response(request)
      response = @responses.delete(request)
      case response
      when ErrorResponse
        if response.retryable?
          send(request, retries: response.retries - 1)
          nil
        else
          response
        end
      else
        response
      end
    end

    private

    # opens a channel to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few channels as possible.
    #
    def bind(uri)
      uri = URI(uri)
      ip = TCPSocket.getaddress(uri.host)
      return @channels.find do |channel|
        ip == channel.remote_ip &&
        uri.port == channel.remote_port &&
        uri.scheme == channel.uri.scheme
      end || begin
        build_channel(uri)
      end
    end

    def build_channel(uri)
      channel = Channel.by(uri, @options) do |request, response|
        @responses[request] = response
      end
      monitor = @selector.register(channel, :rw)
      monitor.value = channel
      @channels << channel
      channel
    end

    def consume(task)
      channel = catch(:close) { task.call }
      close(channel) if channel 
    end
  end
end
