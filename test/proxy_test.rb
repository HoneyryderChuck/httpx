# frozen_string_literal: true

require_relative "test_helper"
require "httpx/plugins/proxy"

class ProxyTest < Minitest::Test
  include HTTPX

  def test_parameters
    params = parameters(username: "user", password: "pass")
    assert params == parameters(username: "user", password: "pass")
    assert params != parameters(username: "user2", password: "pass")
    assert params != parameters
    assert params == URI.parse("http://user:pass@proxy")
    assert params == "http://user:pass@proxy"
    assert params != "bamalam"
    assert params != 1
  end

  def test_parameters_authenticated
    assert parameters(username: "user", password: "pass").authenticated?
    assert !parameters.authenticated?
  end

  def test_parameters_token_authentication
    params = parameters(username: "user", password: "pass")
    assert params.token_authentication == Base64.strict_encode64("user:pass"),
           "it should have base64-rencoded the credentials"
  end

  private

  def parameters(uri: "http://proxy", **args)
    Plugins::Proxy::Parameters.new(uri: uri, **args)
  end
end
