# frozen_string_literal: true

require "uri"
require "net/http"
require "oga"

module ProxyHelper
  private

  def socks4_proxy
    Array(ENV["HTTPX_SOCKS4_PROXY"] || begin
      socks_proxies_list.select { |_, _, version, https| version == "Socks4" && https }
                        .map { |ip, port, _, _| "socks4://#{ip}:#{port}" }
    end)
  end

  def socks4a_proxy
    Array(ENV["HTTPX_SOCKS4A_PROXY"] || begin
      socks_proxies_list.select { |_, _, version, https| version == "Socks4" && https }
                        .map { |ip, port, _, _| "socks4a://#{ip}:#{port}" }
    end)
  end

  def socks5_proxy
    Array(ENV["HTTPX_SOCKS5_PROXY"] || begin
      socks_proxies_list.select { |_, _, version, https| version == "Socks5" && https }
                        .map { |ip, port, _, _| "socks5://#{ip}:#{port}" }
    end)
  end

  def http_proxy
    Array(ENV["HTTPX_HTTP_PROXY"] || begin
      http_proxies_list.map do |ip, port, _|
        "http://#{ip}:#{port}"
      end
    end)
  end

  def http2_proxy
    Array(ENV["HTTPX_HTTP2_PROXY"])
  end

  def https_proxy
    Array(ENV["HTTPX_HTTPS_PROXY"] || begin
      http_proxies_list.select { |_, _, https| https }.map do |ip, port, _|
        "http://#{ip}:#{port}"
      end
    end)
  end

  def ssh_proxy
    Array(ENV["HTTPX_SSH_PROXY"] || begin
      http_proxies_list.select { |_, _, https| https }.map do |ip, port, _|
        "ssh://#{ip}:#{port}"
      end
    end)
  end

  def http_proxies_list
    proxies_list(parse_http_proxies)
      .map do |line|
        ip, port, _, _, _, _, https, _ = line.css("td").map(&:text)
        [ip, port, https == "yes"]
      end.select { |ip, port, _| ip && port } # rubocop:disable Style/MultilineBlockChain
  end

  def socks_proxies_list
    proxies_list(parse_socks_proxies)
      .map do |line|
        ip, port, _, _, version, _, https, _ = line.css("td").map(&:text)
        [ip, port, version, https == "Yes"]
      end.select { |ip, port, _, _| ip && port } # rubocop:disable Style/MultilineBlockChain
  end

  def proxies_list(document)
    row = document.enum_for(:each_node).find do |node|
      next unless node.is_a?(Oga::XML::Element)

      id = node.attribute("id")
      next unless id

      id.value == "proxylisttable"
    end
    row ? row.css("tr") : []
  end

  def parse_http_proxies
    @parse_http_proxies ||= Oga.parse_html(fetch_http_proxies)
  end

  def fetch_http_proxies
    Net::HTTP.get_response(URI("https://www.sslproxies.org/")).body
  end

  def parse_socks_proxies
    @parse_socks_proxies ||= Oga.parse_html(fetch_socks_proxies)
  end

  def fetch_socks_proxies
    Net::HTTP.get_response(URI("https://www.socks-proxy.net/")).body
  end
end
