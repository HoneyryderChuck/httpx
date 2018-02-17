# frozen_string_literal: true

require "uri"
require "net/http"
require "oga"

module ProxyHelper
  private

  def socks4_proxy
    ENV["HTTPX_SOCKS4_PROXY"] || begin
      ip, port, _, _ = socks_proxies_list.select do |_, _, version, https|
        version == "Socks4" && https
      end.sample
      "socks4://#{ip}:#{port}"
    end
  end

  def socks4a_proxy
    ENV["HTTPX_SOCKS4A_PROXY"] || begin
      ip, port, _, _ = socks_proxies_list.select do |_, _, version, https|
        version == "Socks4" && https
      end.sample
      "socks4a://#{ip}:#{port}"
    end
  end

  def socks5_proxy
    ENV["HTTPX_SOCKS5_PROXY"] || begin
      ip, port, _, _ = socks_proxies_list.select do |_, _, version, https|
        version == "Socks5" && https
      end.sample
      "socks5://#{ip}:#{port}"
    end
  end

  def http_proxy
    ENV["HTTPX_HTTP_PROXY"] || begin
      ip, port, _ = http_proxies_list.sample
      "http://#{ip}:#{port}"
    end
  end

  def https_proxy
    ENV["HTTPX_HTTPS_PROXY"] || begin
      ip, port, _ = http_proxies_list.select { |_, _, https| https }.sample
      "http://#{ip}:#{port}"
    end
  end

  def http_proxies_list
    proxies_list(parse_http_proxies)
      .map do |line|
        ip, port, _, _, _, _, https, _ = line.css("td").map(&:text)
        [ip, port, https == "yes"]
      end
  end

  def socks_proxies_list
    proxies_list(parse_socks_proxies)
      .map do |line|
        ip, port, _, _, version, _, https, _ = line.css("td").map(&:text)
        [ip, port, version, https == "Yes"]
      end
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
    @__http__proxies ||= Oga.parse_html(fetch_http_proxies)
  end

  def fetch_http_proxies
    Net::HTTP.get_response(URI("https://www.sslproxies.org/")).body
  end

  def parse_socks_proxies
    @__socks__proxies ||= Oga.parse_html(fetch_socks_proxies)
  end

  def fetch_socks_proxies
    Net::HTTP.get_response(URI("https://www.socks-proxy.net/")).body
  end
end
