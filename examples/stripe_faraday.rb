require "httpx/adapters/faraday"
require "stripe"

Stripe.api_key = "sk_test_123"
Stripe.api_base = "https://localhost:12112"

conn = Faraday.new do |builder|
  builder.use Faraday::Request::Multipart
  builder.use Faraday::Request::UrlEncoded
  builder.use Faraday::Response::RaiseError

  builder.adapter :httpx
end
conn.ssl.verify_mode = 0

client = Stripe::StripeClient.new(conn)

2.times.each do
  response = Stripe::Charge.create({
    amount: 100,
    currency: "usd",
    source: "src_123"
  }, {client: client})
  puts "response: #{response.status}"
  sleep 60 * 3
end
