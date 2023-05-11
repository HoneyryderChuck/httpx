require "httpx"

host = "1.1.1.1"
port = 53

hostname = "google.com"
srv_hostname = "_https._tcp.#{hostname}"
record_type = Resolv::DNS::Resource::IN::SRV

addresses = nil
Resolv::DNS.open(nameserver: host) do |dns|
  addresses = dns.getresources(srv_hostname, record_type)
end

# buffer = HTTPX::Resolver.encode_dns_query(hostname, type: record_type)

# io = UDPSocket.new(Socket::AF_INET)
# size = io.send(buffer.to_s, 0, Socket.sockaddr_in(port, host.to_s))
# data, _ = io.recvfrom(2048)

# addresses = HTTPX::Resolver.decode_dns_answer(data)

puts "(#{hostname}) addresses: #{addresses}"