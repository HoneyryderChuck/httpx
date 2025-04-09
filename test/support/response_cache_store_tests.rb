# frozen_string_literal: true

module ResponseCacheStoreTests
  include HTTPX
  def test_store_cache
    request = make_request("GET", "http://example.com/")
    response = cached_response(request)

    cached_response = store.lookup(request)
    assert cached_response.headers == response.headers
    assert cached_response.body == response.body
    assert store.cached?(request)

    request2 = make_request("GET", "http://example.com/")
    cached_response2 = store.lookup(request2)
    assert cached_response2
    assert cached_response2.headers == response.headers
    assert cached_response2.body == response.body

    request3 = make_request("POST", "http://example.com/")
    assert store.lookup(request3).nil?
  end

  def test_store_error_status
    request = make_request("GET", "http://example.com/")
    _response = cached_response(request, status: 404)
    assert !store.cached?(request)

    _response = cached_response(request, status: 410)
    assert store.cached?(request)
  end

  def test_store_no_store
    request = make_request("GET", "http://example.com/")
    _response = cached_response(request, extra_headers: { "cache-control" => "private, no-store" })
    assert !store.cached?(request)
  end

  def test_store_prepare_maxage
    request = make_request("GET", "http://example.com/")
    response = cached_response(request, extra_headers: { "cache-control" => "max-age=2" })
    assert request.response.nil?

    store.prepare(request)
    assert request.response.headers == response.headers
    assert request.response.body == response.body
    assert request.cached_response.nil?

    request.instance_variable_set(:@response, nil)
    sleep(3)

    store.prepare(request)
    assert request.cached_response == response
    assert request.response.nil?

    request2 = make_request("GET", "http://example2.com/")
    _response2 = cached_response(request2, extra_headers: { "cache-control" => "no-cache, max-age=2" })
    store.prepare(request2)
    assert request2.response.nil?
  end

  def test_store_prepare_expires
    request = make_request("GET", "http://example.com/")
    response = cached_response(request, extra_headers: { "expires" => (Time.now + 2).httpdate })
    assert request.response.nil?

    store.prepare(request)
    assert request.response.headers == response.headers
    assert request.response.body == response.body
    assert request.cached_response.nil?

    request.instance_variable_set(:@response, nil)
    sleep(3)

    store.prepare(request)
    assert request.cached_response == response
    assert request.response.nil?

    request2 = make_request("GET", "http://example2.com/")
    _response2 = cached_response(request2, extra_headers: { "cache-control" => "no-cache", "expires" => (Time.now + 2).httpdate })
    store.prepare(request2)
    assert request2.response.nil?

    request_invalid_expires = make_request("GET", "http://example3.com/")
    _invalid_expires_response = cached_response(request_invalid_expires, extra_headers: { "expires" => "smthsmth" })
    store.prepare(request_invalid_expires)
    assert request_invalid_expires.response.nil?
  end

  def test_store_prepare_invalid_date
    request_invalid_age = make_request("GET", "http://example4.com/")
    response_invalid_age = cached_response(request_invalid_age, extra_headers: { "cache-control" => "max-age=2", "date" => "smthsmth" })
    store.prepare(request_invalid_age)
    assert request_invalid_age.response.headers == response_invalid_age.headers
    assert request_invalid_age.response.body == response_invalid_age.body
  end

  def test_prepare_vary
    request = make_request("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    response = cached_response(request, extra_headers: { "vary" => "Accept" })

    request2 = make_request("GET", "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert !request2.headers.key?("if-none-match")
    assert request2.cached_response.nil?
    request3 = make_request("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.cached_response == response
    assert request3.headers.key?("if-none-match")
    request4 = make_request("GET", "http://example.com/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    store.prepare(request4)
    assert request4.cached_response == response
    assert request4.headers.key?("if-none-match")
  end

  def test_prepare_vary_asterisk
    request = make_request("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    response = cached_response(request, extra_headers: { "vary" => "*" })

    request2 = make_request("GET", "http://example.com/", headers: { "accept" => "text/html" })
    store.prepare(request2)
    assert request.cached_response.nil?
    assert !request2.headers.key?("if-none-match")
    request3 = make_request("GET", "http://example.com/", headers: { "accept" => "text/plain" })
    store.prepare(request3)
    assert request3.cached_response == response
    assert request3.headers.key?("if-none-match")
    request4 = make_request("GET", "http://example.com/", headers: { "accept" => "text/plain", "accept-language" => "en" })
    store.prepare(request4)
    assert request4.cached_response.nil?
    assert !request4.headers.key?("if-none-match")
  end

  private

  def teardown
    store.clear if @store
  end

  def request_class
    @request_class ||= response_cache_session_options.request_class
  end

  def response_class
    @response_class ||= response_cache_session_options.response_class
  end

  def options_class
    @options_class ||= response_cache_session_optionsoptions_class
  end

  def response_cache_session_options
    @response_cache_session_options ||= response_cache_session.class.default_options
  end

  def response_cache_session
    @response_cache_session ||= HTTPX.plugin(:response_cache)
  end

  def make_request(meth, uri, *args)
    response_cache_session.build_request(meth, uri, *args)
  end

  def store
    @store ||= Plugins::ResponseCache::FileStore.new
  end

  def cached_response(request, status: 200, extra_headers: {}, body: "test")
    response = response_class.new(request, status, "2.0", { "date" => Time.now.httpdate, "etag" => "ETAG" }.merge(extra_headers))
    response.body.write(body)
    store.cache(request, response)
    response
  end
end
