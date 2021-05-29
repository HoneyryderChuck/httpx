# frozen_string_literal: true

require "zlib"
require "stringio"
require_relative "test"

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
