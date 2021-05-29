# frozen_string_literal: true

require_relative "test"

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
