#
# From https://ipv6friday.org/blog/2012/11/happy-testing/
#
# The http server accessible via the test doamins is returning empty responses.
# If you want to verify that the correct IP family is being used to establish the connection,
# set HTTPX_DEBUG=2
#
require "httpx"

# URLS  = %w[https://ipv4.test-ipv6.com] * 1
URLS  = %w[https://ipv6.test-ipv6.com] * 1

responses = HTTPX.get(*URLS, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE})

# responses = HTTPX.get(*URLS)
Array(responses).each(&:raise_for_status)
puts "Status: \n"
puts Array(responses).map(&:status)
puts "Payload: \n"
puts Array(responses).map(&:to_s)
