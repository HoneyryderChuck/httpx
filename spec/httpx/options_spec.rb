# frozen_string_literal: true

RSpec.describe HTTPX::Options do
  subject { described_class.new(:response => :body) }

  it "has reader methods for attributes" do
    expect(subject.response).to eq(:body)
  end

  it "coerces to a Hash" do
    expect(subject.to_hash).to be_a(Hash)
  end

  describe "body" do
    let(:opts) { HTTPX::Options.new }
  
    it "defaults to nil" do
      expect(opts.body).to be nil
    end
  
    it "may be specified with with_body" do
      opts2 = opts.with_body("foo")
      expect(opts.body).to be nil
      expect(opts2.body).to eq("foo")
    end
  end

  describe "form" do
    let(:opts) { HTTPX::Options.new }
  
    it "defaults to nil" do
      expect(opts.form).to be nil
    end
  
    it "may be specified with with_form_data" do
      opts2 = opts.with_form(:foo => 42)
      expect(opts.form).to be nil
      expect(opts2.form).to eq(:foo => 42)
    end
  end

  describe "headers" do
    let(:opts) { HTTPX::Options.new }
  
    it "defaults to be empty" do
      expect(opts.headers.to_a).to be_empty
    end
  
    it "may be specified with with_headers" do
      opts2 = opts.with_headers("accept" => "json")
      expect(opts.headers.to_a).to be_empty
      expect(opts2.headers).to eq([%w[Accept json]])
    end
  end

  describe "json" do
    let(:opts) { HTTPX::Options.new }
  
    it "defaults to nil" do
      expect(opts.json).to be nil
    end
  
    it "may be specified with with_json data" do
      opts2 = opts.with_json(:foo => 42)
      expect(opts.json).to be nil
      expect(opts2.json).to eq(:foo => 42)
    end
  end

  describe "merge" do
    let(:opts) { HTTPX::Options.new }
  
    it "supports a Hash" do
      old_response = opts.response
      expect(opts.merge(:response => :body).response).to eq(:body)
      expect(opts.response).to eq(old_response)
    end
  
    it "supports another Options" do
      merged = opts.merge(HTTPX::Options.new(:response => :body))
      expect(merged.response).to eq(:body)
    end
  
    it "merges as excepted in complex cases" do
      # FIXME: yuck :(
  
      foo = HTTPX::Options.new(
        :response  => :body,
        :params    => {:baz => "bar"},
        :form      => {:foo => "foo"},
        :body      => "body-foo",
        :json      => {:foo => "foo"},
        :headers   => {"accept" => "json", "foo" => "foo"},
        :proxy     => {},
      )
  
      bar = HTTPX::Options.new(
        :response   => :parsed_body,
        :params     => {:plop => "plip"},
        :form       => {:bar => "bar"},
        :body       => "body-bar",
        :json       => {:bar => "bar"},
        :keep_alive_timeout => 10,
        :headers            => {"accept" => "xml", "bar" => "bar"},
        :timeout_options    => {:foo => :bar},
        :ssl        => {:foo => "bar"},
        :proxy      => {:proxy_address => "127.0.0.1", :proxy_port => 8080}
      )
  
      expect(foo.merge(bar).to_hash).to eq(
        :response           => :parsed_body,
        :timeout_class      => described_class.default_timeout_class,
        :timeout_options    => {:foo => :bar},
        :params             => {:plop => "plip"},
        :form               => {:bar => "bar"},
        :body               => "body-bar",
        :json               => {:bar => "bar"},
        :keep_alive_timeout => 10,
        :ssl                => {:foo => "bar"},
        :headers            => HTTPX::Headers.new({"Foo" => "foo", "Accept" => "xml", "Bar" => "bar"}),
        :proxy              => {:proxy_address => "127.0.0.1", :proxy_port => 8080},
        :follow             => nil,
        :ssl_context        => nil,
        :cookies            => {},
      )
    end
  end

  describe "new" do
    it "supports a Options instance" do
      opts = HTTPX::Options.new
      expect(HTTPX::Options.new(opts)).to eq(opts)
    end
  
    context "with a Hash" do
      it "coerces :response correctly" do
        opts = HTTPX::Options.new(:response => :object)
        expect(opts.response).to eq(:object)
      end
  
      it "coerces :headers correctly" do
        opts = HTTPX::Options.new(:headers => {"accept" => "json"})
        expect(opts.headers).to eq([%w[Accept json]])
      end
  
      it "coerces :proxy correctly" do
        opts = HTTPX::Options.new(:proxy => {:proxy_address => "127.0.0.1", :proxy_port => 8080})
        expect(opts.proxy).to eq(:proxy_address => "127.0.0.1", :proxy_port => 8080)
      end
  
      it "coerces :form correctly" do
        opts = HTTPX::Options.new(:form => {:foo => 42})
        expect(opts.form).to eq(:foo => 42)
      end
    end
  end

  describe "proxy" do
    let(:opts) { HTTPX::Options.new }
  
    it "defaults to {}" do
      expect(opts.proxy).to eq({})
    end
  
    it "may be specified with with_proxy" do
      opts2 = opts.with_proxy(:proxy_address => "127.0.0.1", :proxy_port => 8080)
      expect(opts.proxy).to eq({})
      expect(opts2.proxy).to eq(:proxy_address => "127.0.0.1", :proxy_port => 8080)
    end
  
    it "accepts proxy address, port, username, and password" do
      opts2 = opts.with_proxy(:proxy_address => "127.0.0.1", :proxy_port => 8080, :proxy_username => "username", :proxy_password => "password")
      expect(opts2.proxy).to eq(:proxy_address => "127.0.0.1", :proxy_port => 8080, :proxy_username => "username", :proxy_password => "password")
    end
  end  
end
