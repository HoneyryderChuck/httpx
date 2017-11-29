# frozen_string_literal: true

require_relative "test_helper"

class ClientTest < Minitest::Test
  include HTTPX

  def test_client_request
    client1 = Client.new
    client2 = Client.new(headers: {"accept" => "text/css"})

    request1 = client1.request(:get, "http://google.com", headers: {"accept" => "text/html"})
    assert request1.headers["accept"] == "text/html", "header hasn't been properly set"

    request2 = client2.request(:get, "http://google.com")
    assert request2.headers["accept"] == "text/css", "header hasn't been properly set"
    
    request3 = client2.request(:get, "http://google.com", headers: {"accept" => "text/javascript"})
    assert request3.headers["accept"] == "text/javascript", "header hasn't been properly set"
  end
end
