# frozen_string_literal: true

require "webrick"
require "logger"
require "zlib"
require "stringio"

class TestServer < WEBrick::HTTPServer
  def initialize(options = {})
    super({
      :BindAddress => "127.0.0.1",
      :Port => 0,
      :AccessLog => File.new(File::NULL),
      :Logger => Logger.new(File::NULL),
    }.merge(options))
  end

  def origin
    sock = listeners.first
    _, sock, ip, _ = sock.addr
    "http://#{ip}:#{sock}"
  end
end

class KeepAliveServer < TestServer
  class KeepAliveApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res["Connection"] = "Keep-Alive"
      res["Keep-Alive"] = "max=2"
      res["Content-Type"] = "application/json"
      res.body = "{\"counter\": 2}"
    end
  end

  def initialize(options = {})
    super
    mount("/", KeepAliveApp)
  end
end

class Expect100Server < TestServer
  class DelayedExpect100App < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(req, res) # rubocop:disable Naming/MethodName
      query = WEBrick::HTTPUtils.parse_query(req.query_string)
      delay = (query["delay"] || 1).to_i
      sleep(delay)
      req.continue
      res.status = 200
      res.body = "echo: #{req.body}"
    end
  end

  class NoExpect100App < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res.body = "echo: #{req.body}"
    end
  end

  def initialize(options = {})
    super
    mount("/no-expect", NoExpect100App)
    mount("/delay", DelayedExpect100App)
  end
end

class NoContentLengthServer < TestServer
  module NoContentLength
    def self.extended(obj)
      super
      obj.singleton_class.class_eval do
        alias_method(:setup_header_without_clength, :setup_header)
        alias_method(:setup_header, :setup_header_with_clength)
      end
    end

    def setup_header_with_clength
      setup_header_without_clength
      header.delete("content-length")
    end
  end

  class NoContentLengthApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      zipped = StringIO.new
      Zlib::GzipWriter.wrap(zipped) do |gz|
        gz.write("helloworld")
      end
      res.body = zipped.string

      res.status = 200
      res["Content-Encoding"] = "gzip"

      res.extend(NoContentLength)
    end
  end

  def initialize(options = {})
    super
    mount("/", NoContentLengthApp)
  end
end

class HTTPTrailersServer < TestServer
  module Trailers
    def self.extended(obj)
      super

      obj.singleton_class.class_eval do
        alias_method(:send_body_without_trailers, :send_body)
        alias_method(:send_body, :send_body_with_trailers)
      end
    end

    def send_body_with_trailers(socket)
      send_body_without_trailers(socket)

      socket.write(+"x-trailer: hello" << "\r\n")
      socket.write(+"x-trailer-2: world" << "\r\n" << "\r\n")
    end
  end

  class HTTPTrailersApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(_req, res) # rubocop:disable Naming/MethodName
      res.status = 200
      res["trailer"] = "x-trailer,x-trailer-2"
      res.body = "trailers"
      res.extend(Trailers)
    end
  end

  def initialize(options = {})
    super
    mount("/", HTTPTrailersApp)
  end
end

class NTLMServer < TestServer
  class NTLMApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(req, res) # rubocop:disable Naming/MethodName
      if req["Authorization"] =~ /^NTLM (.*)/
        authorization = Regexp.last_match(1).unpack("m*")[0] # rubocop:disable Style/UnpackFirst

        case authorization
        when /^NTLMSSP\000\001/
          type2 = "TlRMTVNTUAACAAAADAAMADAAAAABAoEAASNFZ4mr" \
            "ze8AAAAAAAAAAGIAYgA8AAAARABPAE0AQQBJAE4A" \
            "AgAMAEQATwBNAEEASQBOAAEADABTAEUAUgBWAEUA" \
            "UgAEABQAZABvAG0AYQBpAG4ALgBjAG8AbQADACIA" \
            "cwBlAHIAdgBlAHIALgBkAG8AbQBhAGkAbgAuAGMA" \
            "bwBtAAAAAAA="

          res["WWW-Authenticate"] = "NTLM #{type2}"
          res.status = 401
        when /^NTLMSSP\000\003/
          res.body = "ok"
        else
          res["WWW-Authenticate"] = "NTLM"
          res.status = 401
        end
      else
        res["WWW-Authenticate"] = "NTLM"
        res.status = 401
      end
    end
  end

  def initialize(options = {})
    super
    mount("/", NTLMApp)
  end
end
