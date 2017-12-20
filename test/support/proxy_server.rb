# frozen_string_literal: true

require "forwardable"
require "open3"
require "tempfile"

class ProxyServer
  extend Forwardable

  CONF_TEMPLATE = <<-CONF
frontend=%<host>s,%<port>d;no-tls
backend=nghttp2.org,80

  CONF

  def_delegator :@uri, :host
  def_delegator :@uri, :port

  attr_reader :username, :password

  def initialize(proxy_uri:, username: nil, password: nil)
    @uri = URI.parse(proxy_uri)
    @username = username
    @password = password
  end

  def run
    Open3.popen3("nghttpx -s --conf=#{nghttp_conf.path}") do |_, out, err, th|
      begin
        initial_log = +""
        while line = err.gets
          $stderr.puts line
          initial_log << line
          case line
          when /error|fatal/i
            $stderr.puts initial_log
            raise "error starting nghttpx"
          when /LISTEN:/
            break
          end
        end
        yield
      ensure
        Process.kill("TERM",th.pid)
        th.value
      end
    end
  ensure
    @conf.unlink if @conf
  end

  private

  def nghttp_conf
    @conf ||= begin
      file = Tempfile.new("httpx-conf")
      conf = sprintf(CONF_TEMPLATE, host: host, port: port)
      file.write(conf)
      file.close
      file
    end
  end
end
