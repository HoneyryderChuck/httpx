# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/proxy"

class ProxyTest < Minitest::Test
  include HTTPHelpers
  include HTTPX

  def test_parameters_equality
    params = parameters(username: "user", password: "pass")
    assert params == parameters(username: "user", password: "pass")
    assert params != parameters(username: "user2", password: "pass")
    assert params != parameters
    assert params == URI.parse("http://user:pass@proxy")
    assert params == "http://user:pass@proxy"
    assert params != "bamalam"
    assert params != 1
  end

  %w[basic digest ntlm].each do |auth_method|
    define_method :"test_proxy_factory_#{auth_method}" do
      basic_proxy_opts = HTTPX.plugin(:proxy).__send__(:"with_proxy_#{auth_method}_auth", username: "user",
                                                                                          password: "pass").instance_variable_get(:@options)
      proxy = basic_proxy_opts.proxy
      assert proxy.username == "user"
      assert proxy.password == "pass"
      assert proxy.scheme == auth_method
    end
  end

  def test_proxy_unsupported_scheme
    res = HTTPX.plugin(:proxy).with_proxy(uri: "https://proxy:123").get("http://smth.com")
    verify_error_response(res, HTTPX::ProxyError)
    verify_error_response(res, "https: unsupported proxy protocol")
  end

  def test_parameters_can_authenticate_when_authenticator_is_preemptive
    # Authentication::Basic is preemptive — it does not implement
    # can_authenticate? because it always sends credentials and never
    # consumes a challenge. Parameters#can_authenticate? must therefore
    # answer "no" rather than raising NoMethodError.
    params = parameters(username: "user", password: "pass")
    assert params.scheme == "basic"
    assert_equal false, params.can_authenticate?("Basic realm=\"\"")
  end

  def test_parameters_can_authenticate_when_authenticator_supports_challenge
    params = parameters(uri: "http://user:pass@proxy", scheme: "digest")
    assert params.scheme == "digest"
    refute_nil params.can_authenticate?("Digest realm=\"r\", nonce=\"n\", qop=\"auth\"")
  end

  private

  def parameters(uri: "http://proxy", **args)
    Plugins::Proxy::Parameters.new(uri: uri, **args)
  end
end
