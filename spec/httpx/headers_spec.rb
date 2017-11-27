# frozen_string_literal: true

RSpec.describe HTTPX::Headers do
  subject(:headers) { described_class.new }

  it "can become enumerable" do
    expect(headers).to respond_to(:each) 
  end

  describe "#[]=" do
    it "sets header value" do
      headers["accept"] = "application/json"
      expect(headers["accept"]).to eq "application/json"
    end

    it "normalizes header name" do
      headers["Content-Type"] = "application/json"
      expect(headers["content-type"]).to eq "application/json"
    end

    it "overwrites previous value" do
      headers["set-cookie"] = "hoo=ray"
      headers["set-cookie"] = "woo=hoo"
      expect(headers["set-cookie"]).to eq "woo=hoo"
    end

    it "allows set multiple values" do
      headers["set-cookie"] = "hoo=ray"
      headers["set-cookie"] = %w[hoo=ray woo=hoo]
      expect(headers.get("set-cookie")).to eq %w[hoo=ray woo=hoo]
    end

    it "fails with empty header name" do
      expect { headers[""] = "foo bar" }.
        to raise_error HTTPX::HeaderError
    end

    it "fails with invalid header name" do
      expect { headers["foo bar"] = "baz" }.
        to raise_error HTTPX::HeaderError
    end
  end
 
  describe "#delete" do
    before { headers["content-type"] = "application/json" }

    it "removes given header" do
      headers.delete("content-type")
      expect(headers["content-type"]).to be_nil
    end

    it "normalizes header name" do
      headers.delete("Content-Type")
      expect(headers["content-type"]).to be_nil
    end

    it "fails with empty header name" do
      expect { headers.delete("") }.
        to raise_error HTTPX::HeaderError
    end

    it "fails with invalid header name" do
      expect { headers.delete("foo bar") }.
        to raise_error HTTPX::HeaderError
    end
  end

  describe "#add" do
    it "sets header value" do
      headers.add "Accept", "application/json"
      expect(headers["accept"]).to eq "application/json"
    end

    it "normalizes header name" do
      headers.add "Content-Type", "application/json"
      expect(headers["content-type"]).to eq "application/json"
    end

    it "appends new value if header exists" do
      headers.add "set-cookie", "hoo=ray"
      headers.add "set-cookie", "woo=hoo"
      expect(headers.get("set-cookie")).to eq %w[hoo=ray woo=hoo]
    end

    it "allows append multiple values" do
      headers.add "set-cookie", "hoo=ray"
      headers.add "set-cookie", %w[woo=hoo yup=pie]
      expect(headers.get("set-cookie")).to eq %w[hoo=ray woo=hoo yup=pie]
    end

    it "fails with empty header name" do
      expect { headers.add("", "foobar") }.
        to raise_error HTTPX::HeaderError
    end

    it "fails with invalid header name" do
      expect { headers.add("foo bar", "baz") }.
        to raise_error HTTPX::HeaderError
    end
  end

  describe "#get" do
    before { headers["Content-Type"] = "application/json" }

    it "returns array of associated values" do
      expect(headers.get("content-type")).to eq %w[application/json]
    end

    it "normalizes header name" do
      expect(headers.get("Content-Type")).to eq %w[application/json]
    end

    context "when header does not exists" do
      it "returns empty array" do
        expect(headers.get("accept")).to eq []
      end
    end

    it "fails with empty header name" do
      expect { headers.get("") }.
        to raise_error HTTPX::HeaderError
    end

    it "fails with invalid header name" do
      expect { headers.get("foo bar") }.
        to raise_error HTTPX::HeaderError
    end
  end

  describe "#[]" do
    context "when header does not exists" do
      it "returns nil" do
        expect(headers["accept"]).to be_nil
      end
    end

    context "when header has a single value" do
      before { headers["content-type"] = "application/json" }

      it "normalizes header name" do
        expect(headers["content-type"]).to_not be_nil
      end

      it "returns it returns a single value" do
        expect(headers["content-type"]).to eq "application/json"
      end
    end

    context "when header has a multiple values" do
      before do
        headers.add "set-cookie", "hoo=ray"
        headers.add "set-cookie", "woo=hoo"
      end

      it "normalizes header name" do
        expect(headers["set-cookie"]).to_not be_nil
      end

      it "returns array of associated values" do
        expect(headers.get("set-cookie")).to eq %w[hoo=ray woo=hoo]
      end
    end
  end

  describe "#each" do
    before do
      headers.add "set-cookie",   "hoo=ray"
      headers.add "content-type", "application/json"
      headers.add "set-cookie",   "woo=hoo"
    end

    it "yields each key/value pair separatedly" do
      expect { |b| headers.each(&b) }.to yield_control.exactly(3).times
    end

    it "yields headers in the same order they were added" do
      expect { |b| headers.each(&b) }.to yield_successive_args(
        %w[set-cookie hoo=ray],
        %w[set-cookie woo=hoo],
        %w[content-type application/json],
      )
    end

    it "returns self instance if block given" do
      expect(headers.each { |*| }).to be headers
    end

    it "returns Enumerator if no block given" do
      expect(headers.each).to be_a Enumerator
    end
  end

  describe "#dup" do
    before { headers["content-type"] = "application/json" }

    subject(:dupped) { headers.dup }

    it { is_expected.to be_a described_class }
    it { is_expected.not_to be headers }

    it "has headers copied" do
      expect(dupped["content-type"]).to eq "application/json"
    end

    context "modifying a copy" do
      before { dupped["content-type"] = "text/plain" }

      it "modifies dupped copy" do
        expect(dupped["content-type"]).to eq "text/plain"
      end

      it "does not affects original headers" do
        expect(headers["content-type"]).to eq "application/json"
      end
    end
  end

  describe "#merge" do
    before do
      headers["host"] = "example.com"
      headers["accept"] = "application/json"
    end

    subject(:merged) do
      headers.merge "accept" => "plain/text", "cookie" => %w[hoo=ray woo=hoo]
    end

    it { is_expected.to be_a described_class }
    it { is_expected.not_to be headers }

    it "does not affects original headers" do
      expect(merged).to_not eq headers
    end

    it "leaves headers not presented in other as is" do
      expect(merged["host"]).to eq "example.com"
    end

    it "overwrites existing values" do
      expect(merged["accept"]).to eq "plain/text"
    end

    it "appends other headers, not presented in base" do
      expect(merged.get("cookie")).to eq %w[hoo=ray woo=hoo]
    end
  end
end
