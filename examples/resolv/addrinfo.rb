require "socket"

puts Process.pid
sleep 10
puts Addrinfo.getaddrinfo("www.google.com", 80).inspect
sleep 10
puts Addrinfo.getaddrinfo("www.google.com", 80).inspect
sleep 60