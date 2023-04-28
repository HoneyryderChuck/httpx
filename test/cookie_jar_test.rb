# frozen_string_literal: true

require_relative "test_helper"

class CookieJarTest < Minitest::Test
  def test_plugin_cookies_jar
    HTTPX.plugin(:cookies) # force loading the modules

    # Test special cases
    special_jar = HTTPX::Plugins::Cookies::Jar.new
    special_jar.parse(%(a="b"; Path=/, c=d; Path=/, e="f\\"; \\"g"))
    cookies = special_jar[jar_cookies_uri]
    assert(cookies.one? { |cookie| cookie.name == "a" && cookie.value == "b" })
    assert(cookies.one? { |cookie| cookie.name == "c" && cookie.value == "d" })
    assert(cookies.one? { |cookie| cookie.name == "e" && cookie.value == "f\"; \"g" })

    # Test secure parameter
    secure_jar = HTTPX::Plugins::Cookies::Jar.new
    secure_jar.parse(%(a=b; Path=/; Secure))
    assert !secure_jar[jar_cookies_uri(scheme: "https")].empty?, "cookie jar should contain the secure cookie"
    assert secure_jar[jar_cookies_uri(scheme: "http")].empty?, "cookie jar should not contain the secure cookie"

    # Test path parameter
    path_jar = HTTPX::Plugins::Cookies::Jar.new
    path_jar.parse(%(a=b; Path=/cookies))
    assert path_jar[jar_cookies_uri("/")].empty?
    assert !path_jar[jar_cookies_uri("/cookies")].empty?
    assert !path_jar[jar_cookies_uri("/cookies/set")].empty?

    # Test expires
    maxage_jar = HTTPX::Plugins::Cookies::Jar.new
    maxage_jar.parse(%(a=b; Path=/; Max-Age=2))
    assert !maxage_jar[jar_cookies_uri].empty?
    sleep 3
    assert maxage_jar[jar_cookies_uri].empty?

    expires_jar = HTTPX::Plugins::Cookies::Jar.new
    expires_jar.parse(%(a=b; Path=/; Expires=Sat, 02 Nov 2019 15:24:00 GMT))
    assert expires_jar[jar_cookies_uri].empty?

    # regression test
    rfc2616_expires_jar = HTTPX::Plugins::Cookies::Jar.new
    rfc2616_expires_jar.parse(%(a=b; Path=/; Expires=Fri, 17-Feb-2033 12:43:41 GMT))
    assert !rfc2616_expires_jar[jar_cookies_uri].empty?

    # Test domain
    domain_jar = HTTPX::Plugins::Cookies::Jar.new
    domain_jar.parse(%(a=b; Path=/; Domain=.google.com))
    assert domain_jar[jar_cookies_uri].empty?
    assert !domain_jar["http://www.google.com/"].empty?

    ipv4_domain_jar = HTTPX::Plugins::Cookies::Jar.new
    ipv4_domain_jar.parse(%(a=b; Path=/; Domain=137.1.0.12))
    assert ipv4_domain_jar["http://www.google.com/"].empty?
    assert !ipv4_domain_jar["http://137.1.0.12/"].empty?

    ipv6_domain_jar = HTTPX::Plugins::Cookies::Jar.new
    ipv6_domain_jar.parse(%(a=b; Path=/; Domain=[fe80::1]))
    assert ipv6_domain_jar["http://www.google.com/"].empty?
    assert !ipv6_domain_jar["http://[fe80::1]/"].empty?

    # Test duplicate
    dup_jar = HTTPX::Plugins::Cookies::Jar.new
    dup_jar.parse(%(a=c, a=a, a=b))
    cookies = dup_jar[jar_cookies_uri]
    assert cookies.size == 1, "should only have kept one of the received \"a\" cookies"
    cookie = cookies.first
    assert cookie.name == "a", "unexpected name"
    assert cookie.value == "b", "unexpected value, should have been \"b\", instead it's \"#{cookie.value}\""
  end

  def test_plugin_cookies_jar_merge
    HTTPX.plugin(:cookies) # force loading the modules

    jar = HTTPX::Plugins::Cookies::Jar.new
    assert jar.each.to_a == []
    assert jar.merge("a" => "b").each.map { |c| [c.name, c.value] } == [%w[a b]]
    assert jar.merge([HTTPX::Plugins::Cookies::Cookie.new("a", "b")]).each.map { |c| [c.name, c.value] } == [%w[a b]]
    assert jar.merge([{ name: "a", value: "b" }]).each.map { |c| [c.name, c.value] } == [%w[a b]]
  end

  def test_plugins_cookies_cookie
    HTTPX.plugin(:cookies) # force loading the modules

    # match against uris
    acc_c1 = HTTPX::Plugins::Cookies::Cookie.new("a", "b")
    assert acc_c1.send(:acceptable_from_uri?, "https://www.google.com")
    acc_c2 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", domain: ".google.com")
    assert acc_c2.send(:acceptable_from_uri?, "https://www.google.com")
    assert !acc_c2.send(:acceptable_from_uri?, "https://nghttp2.org")
    acc_c3 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", domain: "google.com")
    assert !acc_c3.send(:acceptable_from_uri?, "https://www.google.com")

    # quoting funny characters
    sch_cookie = HTTPX::Plugins::Cookies::Cookie.new("Bar", "value\"4")
    assert sch_cookie.cookie_value == %(Bar="value\\"4")

    # sorting
    c1 = HTTPX::Plugins::Cookies::Cookie.new("a", "b")
    c2 = HTTPX::Plugins::Cookies::Cookie.new("a", "bc")
    assert [c2, c1].sort == [c1, c2]

    c3 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", path: "/cookies")
    assert [c3, c2, c1].sort == [c3, c1, c2]

    c4 = HTTPX::Plugins::Cookies::Cookie.new("a", "b", created_at: (Time.now - (60 * 60 * 24)))
    assert [c4, c3, c2, c1].sort == [c3, c4, c1, c2]
  end

  private

  def jar_cookies_uri(path = "/cookies", scheme: "http")
    "#{scheme}://example.com#{path}"
  end
end
