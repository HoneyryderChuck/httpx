# frozen_string_literal: true

require "webmock/minitest"
require "httpx/adapters/webmock"
require "test_helper"
require "support/http_helpers"

class WebmockTest < Minitest::Test
  include HTTPHelpers

  MOCK_URL_HTTP = "http://www.example.com"
  MOCK_URL_HTTP_EXCEPTION = "http://exception.example.com"
  MOCK_URL_HTTP_TIMEOUT = "http://timeout.example.com"
  MOCK_URL_HTTP_TIMEOUT_RETRIES = "http://timeout-x-times.example.com"

  def setup
    super
    WebMock.enable!
    WebMock.disable_net_connect!
    @stub_http = stub_http_request(:any, MOCK_URL_HTTP)

    @exception_class = Class.new(StandardError)
    @stub_exception = stub_http_request(:any, MOCK_URL_HTTP_EXCEPTION).to_raise(@exception_class.new("exception message"))
    @stub_timeout = stub_http_request(:any, MOCK_URL_HTTP_TIMEOUT).to_timeout
    @stub_timeout_retries = stub_http_request(:any, MOCK_URL_HTTP_TIMEOUT_RETRIES).to_timeout.times(2).then.to_return(body: "body")
  end

  def teardown
    WebMock.reset!
    WebMock.allow_net_connect!
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

  def test_to_raise
    response = http_request(:get, MOCK_URL_HTTP_EXCEPTION)
    assert_requested(@stub_exception)
    assert_equal(@exception_class.new("exception message"), response.error)
  end

  def test_to_timeout
    response = http_request(:get, MOCK_URL_HTTP_TIMEOUT)
    assert_requested(@stub_timeout)
    assert_equal(HTTPX::TimeoutError.new(1, "Timed out"), response.error)
  end

  def test_to_timeout_with_retries
    response = HTTPX.plugin(:retries, max_retries: 3).get(MOCK_URL_HTTP_TIMEOUT_RETRIES)
    assert_requested(@stub_timeout_retries, times: 3)
    assert !response.is_a?(HTTPX::ErrorResponse)
    assert_equal("body", response.to_s)
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
    stub_request(:any, MOCK_URL_HTTP).with(query: hash_including("a" => %w[b c]))
    http_request(:get, "#{MOCK_URL_HTTP}/?a[]=b&a[]=c&x=1")
    assert_requested(:get, MOCK_URL_HTTP,
                     query: hash_including("a" => %w[b c]))
  end

  def test_verification_that_requests_with_query_parameters_correctly_called
    stub_request(:get, MOCK_URL_HTTP).to_return(body: "1")
    stub_request(:get, "#{MOCK_URL_HTTP}/?a[]=b&a[]=c").to_return(body: "2")
    stub_request(:get, "#{MOCK_URL_HTTP}/?test=value").to_return(body: "3")

    response_1 = http_request(:get, MOCK_URL_HTTP)
    response_2 = http_request(:get, MOCK_URL_HTTP, params: { "a" => %w[b c] })
    response_3 = http_request(:get, MOCK_URL_HTTP, params: { test: "value" })

    assert_equal "1", response_1.body.to_s
    assert_equal "2", response_2.body.to_s
    assert_equal "3", response_3.body.to_s

    assert_requested(:get, MOCK_URL_HTTP)
    assert_requested(:get, "#{MOCK_URL_HTTP}/?a[]=b&a[]=c")
    assert_requested(:get, "#{MOCK_URL_HTTP}/?test=value")
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

  def test_webmock_mix_mock_and_real_request
    WebMock.allow_net_connect!

    @stub_http.to_return(status: 200)

    # test webmock callback as well
    responses = {}
    WebMock.after_request do |request_signature, response|
      responses[request_signature.uri.to_s] = response
    end

    # this one ain't stubbed
    real_request_uri = build_uri("/get", "http://#{httpbin}")
    http_request(:get, "#{MOCK_URL_HTTP}/", real_request_uri)

    assert responses.size == 2, "received #{responses.size} instead (#{responses.keys})"
    assert(responses.values.all? { |r| r.status.first == 200 })
  ensure
    WebMock.reset_callbacks
    WebMock.disable_net_connect!
  end

  def test_webmock_disable_after_enable
    WebMock.disable!

    # WebMock is disabled so this will make a real http request
    http_request(:get, "http://#{httpbin}")

    # WebMock is disabled so it should not have registered the request
    assert_not_requested(:get, "http://#{httpbin}")
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

  def http_request(meth, *uris, **options)
    HTTPX.__send__(meth, *uris, **options)
  end
end
