# frozen_string_literal: true

require_relative "test_helper"

class OptionsSpec < Minitest::Test
  include HTTPX

  def test_options_body
    opt1 = Options.new
    assert opt1.body.nil?, "body shouldn't be set by default"
    opt2 = Options.new(:body => "fat")
    assert opt2.body == "fat", "body was not set"
    opt3 = opt1.with_body("fat")
    assert opt3.body == "fat", "body was not set"
  end

  %i[form json].each do |meth|
    define_method :"test_options_#{meth}" do
      opt1 = Options.new
      assert opt1.public_send(meth).nil?, "#{meth} shouldn't be set by default"
      opt2 = Options.new(meth => { "foo" => "bar" })
      assert opt2.public_send(meth) == { "foo" => "bar" }, "#{meth} was not set"
      opt3 = opt1.public_send(:"with_#{meth}", "foo" => "bar")
      assert opt3.public_send(meth) == { "foo" => "bar" }, "option was not set"
    end
  end

  def test_options_headers
    opt1 = Options.new
    assert opt1.headers.to_a.empty?, "headers should be empty"
    opt2 = Options.new(:headers => { "accept" => "*/*" })
    assert opt2.headers.to_a == [%w[accept */*]], "headers are unexpected"
    opt3 = opt1.with_headers("accept" => "*/*")
    assert opt3.headers.to_a == [%w[accept */*]], "headers are unexpected"
  end

  def test_options_merge
    opts = Options.new(body: "fat")
    assert opts.merge(body: "thin").body == "thin", "parameter hasn't been merged"
    assert opts.body == "fat", "original parameter has been mutated after merge"

    opt2 = Options.new(body: "short")
    assert opts.merge(opt2).body == "short", "options parameter hasn't been merged"

    foo = Options.new(
      :form      => { :foo => "foo" },
      :headers   => { :accept => "json", :foo => "foo" },
    )

    bar = Options.new(
      :form => { :bar => "bar" },
      :headers => { :accept => "xml", :bar => "bar" },
      :ssl => { :foo => "bar" },
    )

    assert foo.merge(bar).to_hash == {
      :io                 => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :debug              => nil,
      :debug_level        => 1,
      :params             => nil,
      :json               => nil,
      :body               => nil,
      :follow             => nil,
      :window_size        => 16_384,
      :body_threshold_size => 114_688,
      :form               => { :bar => "bar" },
      :timeout            => Timeout.new,
      :ssl                => { :foo => "bar" },
      :http2_settings     => { :settings_enable_push => 0 },
      :fallback_protocol  => "http/1.1",
      :headers            => { "Foo" => "foo", "Accept" => "xml", "Bar" => "bar" },
      :max_concurrent_requests => 100,
      :max_retries        => 3,
      :request_class      => bar.request_class,
      :response_class     => bar.response_class,
      :headers_class      => bar.headers_class,
      :request_body_class => bar.request_body_class,
      :response_body_class => bar.response_body_class,
    }, "options haven't merged correctly"
  end

  def test_options_new
    opts = Options.new
    assert Options.new(opts) == opts, "it should have kept the same reference"
  end

  def test_options_to_hash
    opts = Options.new
    assert opts.to_hash.is_a?(Hash)
  end
end
