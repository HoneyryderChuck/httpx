require "httpx"


FILE = "test/support/fixtures/image.jpg"

BUCKET_URL = "https://httpx-tests.s3.eu-west-1.amazonaws.com"

aws_httpx = HTTPX.plugin(:aws_sdk_authentication).aws_sdk_authentication(service: "s3")


requests = (1..5).map{ |i| aws_httpx.build_request(:put, BUCKET_URL + "/image-#{i}", body: File.new(FILE)) }
responses = aws_httpx.request(*requests)
# responses = aws_httpx.get(BUCKET_URL + "/image")
Array(responses).each(&:raise_for_status)
puts "Status: \n"
puts Array(responses).map(&:status)
puts "Payload: \n"
puts Array(responses).map(&:to_s)

