# frozen_string_literal: true

require "socket"
require "timeout"

module HTTPX
  class Connection
    require "httpx/connection/http2"

    PROTOCOLS = {
      "h2" => HTTP2
    }

    CONNECTION_TIMEOUT = 2 

    def initialize(**options)
      @options = options
      @connection_timeout = options.fetch(:connection_timeout, CONNECTION_TIMEOUT)
      @channels = {}
      @responses = {}
    end

    def bind(uri)
      uri = URI(uri)
      ip = TCPSocket.getaddress(uri.host)
      return @channels.values.find do |io|
        ip == io.remote_ip && uri.port == io.remote_port
      end || begin
        scheme = Scheme.by(uri)
        @channels[scheme.to_io] = scheme 
      end
    end

    def <<(request)
      channel = bind(request.uri)
      raise "no channel available" unless channel

      channel.processor ||= begin
        pr = PROTOCOLS[channel.protocol].new
        pr.on(:response) do |request, response|
          @responses[request] = response
        end
        pr
      end
      channel.send(request)
    end

    def response(request)
      @responses[request]
    end

    def process_events(timeout: @connection_timeout) 
      rmonitors = @channels.values
      wmonitors = rmonitors.reject(&:empty?)
      readers, writers = IO.select(rmonitors, wmonitors, nil, timeout)
      raise Timeout::Error, "timed out waiting for data" if readers.nil? && writers.nil?
      readers.each do |reader|
        reader.dread
      end if readers
      writers.each do |writer|
        writer.dwrite
      end if writers
    end
  end
end
