# frozen_string_literal: true

require "socket"
require "timeout"

require "httpx/channel"

module HTTPX
  class Connection
    def initialize(options)
      @options = Options.new(options)
      @operation_timeout = options.operation_timeout
      @channels = []
      @responses = {}
    end

    # opens a channel to the IP reachable through +uri+.
    # Many hostnames are reachable through the same IP, so we try to
    # maximize pipelining by opening as few channels as possible.
    #
    def bind(uri)
      uri = URI(uri)
      ip = TCPSocket.getaddress(uri.host)
      return @channels.find do |io|
        ip == io.remote_ip && uri.port == io.remote_port
      end || begin
        channel = Channel.by(uri)
        @channels << channel 
        channel
      end
    end

    def <<(request)
      channel = bind(request.uri)
      raise "no channel available" unless channel

      channel.send(request) do |request, response|
        @responses[request] = response
      end
    end

    def response(request)
      @responses.delete(request)
    end

    def process_events(timeout: @operation_timeout) 
      rmonitors = @channels
      wmonitors = rmonitors.reject(&:empty?)
      readers, writers = IO.select(rmonitors, wmonitors, nil, timeout)
      raise Timeout::Error, "timed out waiting for data" if readers.nil? && writers.nil?
      readers.each do |reader|
        channel = catch(:close) { reader.dread }
        close(channel) if channel 
      end if readers
      writers.each do |writer|
        channel = catch(:close) { writer.dwrite }
        close(channel) if channel 
      end if writers
    end

    def close(channel = nil)
      if channel
        @channels.delete(channel)
        channel.close
      else
        while ch = @channels.shift
          ch.close
        end 
      end
    end
  end
end
