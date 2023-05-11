# frozen_string_literal: true

require "resolv"
require "httpx"

host = "127.0.0.11"
port = 53

# srv_hostname = "aerserv-bc-us-east.bidswitch.net"
record_type = Resolv::DNS::Resource::IN::A

# # addresses = nil
# # Resolv::DNS.open(nameserver: host) do |dns|
# #   require "pry-byebug"; binding.pry
# #   addresses = dns.getresources(srv_hostname, record_type)
# # end

# message_id = 1
# buffer = HTTPX::Resolver.encode_dns_query(srv_hostname, type: record_type, message_id: message_id)

# io = TCPSocket.new(host, port)
# buffer[0, 2] = [buffer.size, message_id].pack("nn")
# io.write(buffer.to_s)
# data, _ = io.readpartial(2048)
# size = data[0, 2].unpack1("n")
# answer = data[2..-1]
# answer << io.readpartial(size) if size > answer.bytesize

# addresses = HTTPX::Resolver.decode_dns_answer(answer)

# puts "(#{srv_hostname}) addresses: #{addresses}"

srv_hostname = "www.sfjewjfwigiewpgwwg-native-1.com"
socket = UDPSocket.new
buffer = HTTPX::Resolver.encode_dns_query(srv_hostname, type: record_type)
socket.send(buffer.to_s, 0, host, port)
recv, _ = socket.recvfrom(512)
puts "received #{recv.bytesize} bytes..."
addresses = HTTPX::Resolver.decode_dns_answer(recv)
puts "(#{srv_hostname}) addresses: #{addresses}"
