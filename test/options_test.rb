# frozen_string_literal: true

require_relative "test_helper"

class OptionsTest < Minitest::Test
  include HTTPX

  def test_options_unknown
    ex = assert_raises(Error) { Options.new(foo: "bar") }
    assert ex.message == "unknown option: foo", ex.message
  end

  def test_options_body
    opt1 = Options.new
    assert opt1.body.nil?, "body shouldn't be set by default"
    opt2 = Options.new(:body => "fat")
    assert opt2.body == "fat", "body was not set"
  end

  %i[form json xml].each do |meth|
    define_method :"test_options_#{meth}" do
      opt1 = Options.new
      assert opt1.public_send(meth).nil?, "#{meth} shouldn't be set by default"
      opt2 = Options.new(meth => { "foo" => "bar" })
      assert opt2.public_send(meth) == { "foo" => "bar" }, "#{meth} was not set"
    end
  end

  def test_options_headers
    opt1 = Options.new
    assert opt1.headers.to_a.empty?, "headers should be empty"
    opt2 = Options.new(:headers => { "accept" => "*/*" })
    assert opt2.headers.to_a == [%w[accept */*]], "headers are unexpected"
  end

  def test_options_merge_hash
    opts = Options.new(body: "fat")
    merged_opts = opts.merge(body: "thin")
    assert merged_opts.body == "thin", "parameter hasn't been merged"
    assert opts.body == "fat", "original parameter has been mutated after merge"
    assert !opts.equal?(merged_opts), "merged options should be a different object"
  end

  def test_options_merge_options
    opts = Options.new(body: "fat")
    merged_opts2 = opts.merge(Options.new(body: "short"))
    assert opts.body == "fat", "original parameter has been mutated after merge"
    assert merged_opts2.body == "short", "options parameter hasn't been merged"
    assert !opts.equal?(merged_opts2), "merged options should be a different object"
  end

  def test_options_merge_options_empty_hash
    opts = Options.new(body: "fat")
    merged_opts3 = opts.merge({})
    assert opts.equal?(merged_opts3), "merged options should be the same object"
  end

  def test_options_merge_same_options
    opts = Options.new(body: "fat")

    merged_opts4 = opts.merge({ body: "fat" })
    assert opts.equal?(merged_opts4), "merged options should be the same object"

    merged_opts5 = opts.merge(Options.new(body: "fat"))
    assert opts.equal?(merged_opts5), "merged options should be the same object"
  end

  def test_options_merge_origin_uri
    opts = Options.new(origin: "http://example.com")
    merged_opts = opts.merge(Options.new(origin: "http://example2.com"))
    assert merged_opts.origin == URI("http://example2.com")

    merged_opts = opts.merge({ origin: "http://example2.com" })
    assert merged_opts.origin == URI("http://example2.com")
  end

  def test_options_merge_attributes_match
    foo = Options.new(
      :form => { :foo => "foo" },
      :headers => { :accept => "json", :foo => "foo" },
    )

    bar = Options.new(
      :form => { :bar => "bar" },
      :headers => { :accept => "xml", :bar => "bar" },
      :ssl => { :foo => "bar" },
    )

    expected = {
      :io => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :max_requests => Float::INFINITY,
      :debug => nil,
      :debug_level => 1,
      :params => nil,
      :json => nil,
      :xml => nil,
      :body => nil,
      :buffer_size => 16_384,
      :window_size => 16_384,
      :body_threshold_size => 114_688,
      :form => { foo: "foo", :bar => "bar" },
      :timeout => {
        connect_timeout: 60,
        settings_timeout: 10,
        operation_timeout: nil,
        keep_alive_timeout: 20,
        read_timeout: 60,
        write_timeout: 60,
        request_timeout: nil,
      },
      :ssl => { :foo => "bar" },
      :http2_settings => { :settings_enable_push => 0 },
      :fallback_protocol => "http/1.1",
      :supported_compression_formats => %w[gzip deflate],
      :compress_request_body => true,
      :decompress_response_body => true,
      :headers => { "accept" => "xml", "foo" => "foo", "bar" => "bar" },
      :max_concurrent_requests => nil,
      :request_class => bar.request_class,
      :response_class => bar.response_class,
      :headers_class => bar.headers_class,
      :request_body_class => bar.request_body_class,
      :response_body_class => bar.response_body_class,
      :connection_class => bar.connection_class,
      :options_class => bar.options_class,
      :transport => nil,
      :transport_options => nil,
      :addresses => nil,
      :persistent => false,
      :resolver_class => bar.resolver_class,
      :resolver_options => bar.resolver_options,
      :ip_families => bar.ip_families,
    }.compact

    assert foo.merge(bar).to_hash == expected, "options haven't merged correctly"
  end unless ENV.key?("HTTPX_DEBUG")

  def test_options_new
    opts = Options.new
    assert Options.new(opts).equal?(opts), "it should be the same options object"

    opts_class = Class.new(Options)
    opts2 = opts_class.new
    assert Options.new(opts2).equal?(opts2), "it should return the most enhanced options object if build from Options"

    assert opts_class.new(opts2).equal?(opts2), "returns the same object it using the same meta-class"
  end

  def test_options_to_hash
    opts = Options.new
    assert opts.to_hash.is_a?(Hash)
  end
end
