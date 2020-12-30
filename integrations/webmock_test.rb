# frozen_string_literal: true

require "test_helper"
require "webmock/minitest"
require "httpx/adapters/webmock"

class WebmockTest < Minitest::Test
  MOCK_URL_HTTP = "http://www.example.com"
  MOCK_URL_HTTPS = "https://www.example.com"

  def setup
    super
    WebMock.enable!
    @stub_http = stub_http_request(:any, MOCK_URL_HTTP)
    @stub_https = stub_http_request(:any, MOCK_URL_HTTPS)
  end

  def teardown
    WebMock.reset!
    WebMock.disable!
  end

  def test_assert_requested_with_stub_and_block_raises_error
    assert_raises ArgumentError do
      assert_requested(@stub_http) {}
    end
  end

  def test_assert_not_requested_with_stub_and_block_raises_error
    assert_raises ArgumentError do
      assert_not_requested(@stub_http) {}
    end
  end

  def test_error_on_non_stubbed_request
    assert_raise_with_message(WebMock::NetConnectNotAllowedError, Regexp.new(
                                                                    "Real HTTP connections are disabled. " \
                                                                    "Unregistered request: GET http://www.example.net/ with headers"
                                                                  )) do
      http_request(:get, "http://www.example.net/")
    end
  end

  def test_verification_that_expected_request_occured
    http_request(:get, "#{MOCK_URL_HTTP}/")
    assert_requested(:get, MOCK_URL_HTTP, times: 1)
    assert_requested(:get, MOCK_URL_HTTP)
  end

  def test_verification_that_expected_stub_occured
    http_request(:get, "#{MOCK_URL_HTTP}/")
    assert_requested(@stub_http, times: 1)
    assert_requested(@stub_http)
  end

  def test_verification_that_expected_request_didnt_occur
    expected_message = "The request GET #{MOCK_URL_HTTP}/ was expected to execute 1 time but it executed 0 times" \
      "\n\nThe following requests were made:\n\nNo requests were made.\n" \
      "============================================================"
    assert_raise_with_message(MiniTest::Assertion, expected_message) do
      assert_requested(:get, MOCK_URL_HTTP)
    end
  end

  def test_verification_that_expected_stub_didnt_occur
    expected_message = "The request ANY #{MOCK_URL_HTTP}/ was expected to execute 1 time but it executed 0 times" \
      "\n\nThe following requests were made:\n\nNo requests were made.\n" \
      "============================================================"
    assert_raise_with_message(MiniTest::Assertion, expected_message) do
      assert_requested(@stub_http)
    end
  end

  def test_verification_that_expected_request_occured_with_body_and_headers
    http_request(:get, "#{MOCK_URL_HTTP}/",
                 body: "abc", headers: { "A" => "a" })
    assert_requested(:get, MOCK_URL_HTTP,
                     body: "abc", headers: { "A" => "a" })
  end

  def test_verification_that_expected_request_occured_with_query_params
    stub_request(:any, MOCK_URL_HTTP).with(query: hash_including({ "a" => %w[b c] }))
    http_request(:get, "#{MOCK_URL_HTTP}/?a[]=b&a[]=c&x=1")
    assert_requested(:get, MOCK_URL_HTTP,
                     query: hash_including({ "a" => %w[b c] }))
  end

  def test_verification_that_expected_request_not_occured_with_query_params
    stub_request(:any, MOCK_URL_HTTP).with(query: hash_including(a: %w[b c]))
    stub_request(:any, MOCK_URL_HTTP).with(query: hash_excluding(a: %w[b c]))
    http_request(:get, "#{MOCK_URL_HTTP}/?a[]=b&a[]=c&x=1")
    assert_not_requested(:get, MOCK_URL_HTTP, query: hash_excluding("a" => %w[b c]))
  end

  def test_verification_that_expected_request_occured_with_excluding_query_params
    stub_request(:any, MOCK_URL_HTTP).with(query: hash_excluding("a" => %w[b c]))
    http_request(:get, "#{MOCK_URL_HTTP}/?a[]=x&a[]=y&x=1")
    assert_requested(:get, MOCK_URL_HTTP, query: hash_excluding("a" => %w[b c]))
  end

  def test_verification_that_non_expected_request_didnt_occur
    expected_message = Regexp.new(
      "The request GET #{MOCK_URL_HTTP}/ was not expected to execute but it executed 1 time\n\n" \
      "The following requests were made:\n\nGET #{MOCK_URL_HTTP}/ with headers .+ was made 1 time\n\n" \
      "============================================================"
    )
    assert_raise_with_message(MiniTest::Assertion, expected_message) do
      http_request(:get, "http://www.example.com/")
      assert_not_requested(:get, "http://www.example.com")
    end
  end

  def test_refute_requested_alias
    expected_message = Regexp.new(
      "The request GET #{MOCK_URL_HTTP}/ was not expected to execute but it executed 1 time\n\n" \
      "The following requests were made:\n\nGET #{MOCK_URL_HTTP}/ with headers .+ was made 1 time\n\n" \
      "============================================================"
    )
    assert_raise_with_message(MiniTest::Assertion, expected_message) do
      http_request(:get, "#{MOCK_URL_HTTP}/")
      refute_requested(:get, MOCK_URL_HTTP)
    end
  end

  def test_verification_that_non_expected_stub_didnt_occur
    expected_message = Regexp.new(
      "The request ANY #{MOCK_URL_HTTP}/ was not expected to execute but it executed 1 time\n\n" \
      "The following requests were made:\n\nGET #{MOCK_URL_HTTP}/ with headers .+ was made 1 time\n\n" \
      "============================================================"
    )
    assert_raise_with_message(MiniTest::Assertion, expected_message) do
      http_request(:get, "#{MOCK_URL_HTTP}/")
      assert_not_requested(@stub_http)
    end
  end

  private

  def assert_raise_with_message(e, message, &block)
    e = assert_raises(e, &block)
    if message.is_a?(Regexp)
      assert_match(message, e.message)
    else
      assert_equal(message, e.message)
    end
  end

  def http_request(meth, uri, options = {})
    session = HTTPX
    uri = URI.parse(uri)
    session = session.plugin(:basic_authentication, username: uri.user, password: password) if uri.user
    session.request(meth, uri, **options)
  end
end
