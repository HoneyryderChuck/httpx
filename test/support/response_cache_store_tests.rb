# frozen_string_literal: true

module ResponseCacheStoreTests
  include HTTPX
  def test_store_cache
    request = make_request("GET", "http://store-cache/")
    response = cached_response(request)

    cached_response = store.get(request)
    assert cached_response.headers == response.headers
    assert cached_response.body == response.body
    assert store.get(request)

    request2 = make_request("GET", "http://store-cache/")
    cached_response2 = store.get(request2)
    assert cached_response2
    assert cached_response2.headers == response.headers
    assert cached_response2.body == response.body

    request3 = make_request("POST", "http://store-cache/")
    assert store.get(request3).nil?
  end

  def test_store_prepare_maxage
    request = make_request("GET", "http://prepare-maxage/")
    response = cached_response(request, extra_headers: { "cache-control" => "max-age=2" })
    assert request.response.nil?

    prepare(request)
    assert request.response
    assert request.response.headers == response.headers
    assert request.response.body == response.body
    assert request.cached_response.nil?

    request.instance_variable_set(:@response, nil)
    sleep(3)

    prepare(request)
    assert request.cached_response
    assert request.cached_response.headers == response.headers
    assert request.cached_response.body == response.body
    assert request.response.nil?

    request2 = make_request("GET", "http://prepare-cache-2.com/")
    cached_response(request2, extra_headers: { "cache-control" => "no-cache, max-age=2" })
    prepare(request2)
    assert request2.response.nil?
  end

  def test_store_prepare_expires
    request = make_request("GET", "http://prepare-expires/")
    response = cached_response(request, extra_headers: { "expires" => (Time.now + 5).httpdate })
    assert request.response.nil?

    prepare(request)
    assert request.response
    assert request.response.headers == response.headers
    assert request.response.body == response.body
    assert request.cached_response.nil?

    request.instance_variable_set(:@response, nil)
    sleep(6)

    prepare(request)
    assert request.cached_response
    assert request.cached_response.headers == response.headers
    assert request.cached_response.body == response.body
    assert request.response.nil?

    request2 = make_request("GET", "http://prepare-expires-2/")
    cached_response(request2, extra_headers: { "cache-control" => "no-cache", "expires" => (Time.now + 2).httpdate })
    prepare(request2)
    assert request2.response.nil?

    request_invalid_expires = make_request("GET", "http://prepare-expires-3/")
    _invalid_expires_response = cached_response(request_invalid_expires, extra_headers: { "expires" => "smthsmth" })
    prepare(request_invalid_expires)
    assert request_invalid_expires.response.nil?
  end

  def test_store_prepare_invalid_date
    request_invalid_age = make_request("GET", "http://prepare-expires-4/")
    response_invalid_age = cached_response(request_invalid_age, extra_headers: { "cache-control" => "max-age=2", "date" => "smthsmth" })
    prepare(request_invalid_age)
    assert request_invalid_age.response
    assert request_invalid_age.response.headers == response_invalid_age.headers
    assert request_invalid_age.response.body == response_invalid_age.body
  end

  def test_prepare_vary
    request = make_request("GET", "http://prepare-vary/", headers: { "accept" => "text/plain" })
    response = cached_response(request, extra_headers: { "vary" => "Accept" })

    request2 = make_request("GET", "http://prepare-vary/", headers: { "accept" => "text/html" })
    prepare(request2)
    assert !request2.headers.key?("if-none-match")
    assert request2.cached_response.nil?
    request3 = make_request("GET", "http://prepare-vary/", headers: { "accept" => "text/plain" })
    prepare(request3)
    assert request3.cached_response
    assert request3.cached_response.headers == response.headers
    assert request3.cached_response.body == response.body
    assert request3.headers.key?("if-none-match")
    request4 = make_request("GET", "http://prepare-vary/", headers: { "accept" => "text/plain", "user-agent" => "Linux Bowser" })
    prepare(request4)
    assert request4.cached_response
    assert request4.cached_response.headers == response.headers
    assert request4.cached_response.body == response.body
    assert request4.headers.key?("if-none-match")
  end

  def test_prepare_vary_asterisk
    request = make_request("GET", "http://prepare-vary-asterisk/", headers: { "accept" => "text/plain" })
    response = cached_response(request, extra_headers: { "vary" => "*" })

    request2 = make_request("GET", "http://prepare-vary-asterisk/", headers: { "accept" => "text/html" })
    prepare(request2)
    assert request.cached_response.nil?
    assert !request2.headers.key?("if-none-match")
    request3 = make_request("GET", "http://prepare-vary-asterisk/", headers: { "accept" => "text/plain" })
    prepare(request3)
    assert request3.cached_response
    assert request3.cached_response.headers == response.headers
    assert request3.cached_response.body == response.body
    assert request3.headers.key?("if-none-match")
    request4 = make_request("GET", "http://prepare-vary-asterisk/", headers: { "accept" => "text/plain", "accept-language" => "en" })
    prepare(request4)
    assert request4.cached_response.nil?
    assert !request4.headers.key?("if-none-match")
  end

  private

  def teardown
    response_cache_session.clear_response_cache
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
    @response_cache_session ||= HTTPX.plugin(:response_cache, response_cache_store: store_class.new)
  end

  def make_request(meth, uri, *args)
    response_cache_session.build_request(meth, uri, *args)
  end

  def store_class
    raise NotImplementedError, "must define a `store_class` method"
  end

  def store
    response_cache_session.class.default_options.response_cache_store
  end

  def cached_response(request, status: 200, extra_headers: {}, body: "test")
    response = response_class.new(request, status, "2.0", { "date" => Time.now.httpdate, "etag" => "ETAG" }.merge(extra_headers))
    response.body.write(body)
    store.set(request, response)
    response
  end

  def prepare(request)
    response_cache_session.send(:prepare_cache, request)
  end
end
