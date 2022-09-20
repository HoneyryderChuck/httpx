# frozen_string_literal: true

require "resolv"
require "socket"

# from https://gist.github.com/peterc/1425383

class SlowDNSServer
  attr_reader :queries, :answers

  def initialize(timeout)
    @port = next_available_port
    @can_log = ENV.key?("HTTPX_DEBUG")
    @timeout = timeout
    @queries = 0
    @answers = 0
  end

  def nameserver
    ["127.0.0.1", @port]
  end

  def start
    Socket.udp_server_loop(@port) do |query, src|
      @queries += 1
      sleep(@timeout)
      src.reply(dns_response(query))
      @answers += 1
    end
  end

  private

  def extract_domain(data)
    domain = +""

    # Check "Opcode" of question header for valid question
    if (data[2].ord & 120).zero?
      # Read QNAME section of question section
      # DNS header section is 12 bytes long, so data starts at offset 12

      idx = 12
      len = data[idx].ord
      # Strings are rendered as a byte containing length, then text.. repeat until length of 0
      until len.zero?
        domain << "#{data[idx + 1, len]}."
        idx += len + 1
        len = data[idx].ord
      end
    end
    domain
  end

  def dns_response(query)
    domain = extract_domain(query)
    ip = Resolv.getaddress(domain)
    cname = ip =~ /[a-z]/

    # Valid response header
    response = "#{query[0, 2]}\x81\x00#{query[4, 2] * 2}\x00\x00\x00\x00".b

    # Append original question section
    response << query[12..-1].b

    # Use pointer to refer to domain name in question section
    response << "\xc0\x0c".b

    # Set response type accordingly
    response << (cname ? "\x00\x05".b : "\x00\x01".b)

    # Set response class (IN)
    response << "\x00\x01".b

    # TTL in seconds
    response << [120].pack("N").b

    # Calculate RDATA - we need its length in advance
    rdata = if cname
      ip.split(".").map { |a| a.length.chr + a }.join << "\x00"
    else
      # Append IP address as four 8 bit unsigned bytes
      ip.split(".").map(&:to_i).pack("C*")
    end

    # RDATA is 4 bytes
    response << [rdata.length].pack("n").b
    response << rdata.b
    response
  end

  def next_available_port
    udp = UDPSocket.new
    udp.bind("127.0.0.1", 0)
    udp.addr[1]
  ensure
    udp.close
  end
end
