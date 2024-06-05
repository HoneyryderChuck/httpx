# frozen_string_literal: true

require "logger"

class TestServer < WEBrick::HTTPServer
  def initialize(options = {})
    super({
      :BindAddress => "127.0.0.1",
      :Port => 0,
      :AccessLog => File.new(File::NULL),
      :Logger => Logger.new(File::NULL),
    }.merge(options))
  end

  def origin
    sock = listeners.first
    _, port, ip, _ = sock.addr
    scheme = @config[:SSLEnable] ? URI::HTTPS : URI::HTTP
    scheme.build(host: ip, port: port)
  end
end

class TestHTTP2Server
  attr_reader :origin

  def initialize
    @port = 0
    @host = "localhost"

    @server = TCPServer.new(0)

    @origin = "https://localhost:#{@server.addr[1]}"

    ctx = OpenSSL::SSL::SSLContext.new

    certs_dir = File.expand_path(File.join("..", "..", "ci", "certs"), __FILE__)

    ctx.ca_file = File.join(certs_dir, "ca-bundle.crt")
    ctx.cert = OpenSSL::X509::Certificate.new(File.read(File.join(certs_dir, "server.crt")))
    ctx.key = OpenSSL::PKey.read(File.read(File.join(certs_dir, "server.key")))

    ctx.ssl_version = :TLSv1_2
    ctx.alpn_protocols = ["h2"]

    ctx.alpn_select_cb = lambda do |protocols|
      raise "Protocol h2 is required" unless protocols.include?("h2")

      "h2"
    end

    @server = OpenSSL::SSL::SSLServer.new(@server, ctx)
  end

  def shutdown
    @server.close
  end

  def start
    begin
      loop do
        sock = @server.accept

        conn = HTTP2Next::Server.new
        handle_connection(conn, sock)
        handle_socket(conn, sock)
      end
    rescue IOError
    end
  end

  private

  def handle_stream(_conn, stream)
    stream.on(:half_close) do
      response = "OK"
      stream.headers({
                       ":status" => "200",
                       "content-length" => response.bytesize.to_s,
                       "content-type" => "text/plain",
                     }, end_stream: false)
      stream.data(response, end_stream: true)
    end
  end

  def handle_connection(conn, sock)
    conn.on(:frame) do |bytes|
      # puts "Sending bytes: #{bytes.unpack("H*").first}"
      sock.print bytes
      sock.flush
    end

    conn.on(:goaway) do
      sock.close
    end
    conn.on(:stream) do |stream|
      handle_stream(conn, stream)
    end
  end

  def handle_socket(conn, sock)
    while !sock.closed? && !(sock.eof? rescue true) # rubocop:disable Style/RescueModifier
      data = sock.readpartial(1024)
      # puts "Received bytes: #{data.unpack("H*").first}"

      begin
        conn << data
      rescue StandardError => e
        puts "#{e.class} exception: #{e.message} - closing socket."
        puts e.backtrace
        sock.close
      end
    end
  end
end

class TestDNSResolver
  attr_reader :queries, :answers

  def initialize(port = next_available_port, socket_type = :udp)
    @port = port
    @can_log = ENV.key?("HTTPX_DEBUG")
    @queries = 0
    @answers = 0
    @socket_type = socket_type
  end

  def nameserver
    ["127.0.0.1", @port]
  end

  def start
    if @socket_type == :udp
      Socket.udp_server_loop(@port) do |query, src|
        puts "bang bang"
        @queries += 1
        src.reply(dns_response(query))
        @answers += 1
      end
    elsif @socket_type == :tcp
      Socket.tcp_server_loop(@port) do |sock, _addrinfo|
        begin
          loop do
            query = sock.readpartial(2048)
            size = query[0, 2].unpack1("n")
            query = query.byteslice(2..-1)
            query << sock.readpartial(size - query.size) while query.size < size
            @queries += 1
            answer = dns_response(query)

            answer.prepend([answer.size].pack("n"))
            sock.write(answer)
            @answers += 1
          end
        rescue EOFError
        end
      end
    end
  end

  private

  def dns_response(query)
    domain = extract_domain(query)
    ip = resolve(domain)

    response = response_header(query)
    response << question_section(query)
    response << answer_section(ip)
    response
  end

  def resolve(domain)
    Resolv.getaddress(domain)
  end

  def response_header(query)
    "#{query[0, 2]}\x81\x00#{query[4, 2] * 2}\x00\x00\x00\x00".b
  end

  def question_section(query)
    # Append original question section
    section = query[12..-1].b

    # Use pointer to refer to domain name in question section
    section << "\xc0\x0c".b

    section
  end

  def answer_section(ip)
    cname = ip =~ /[a-z]/

    # Set response type accordingly
    section = (cname ? "\x00\x05".b : "\x00\x01".b)

    # Set response class (IN)
    section << "\x00\x01".b

    # TTL in seconds
    section << [120].pack("N").b

    # Calculate RDATA - we need its length in advance
    rdata = if cname
      ip.split(".").map { |a| a.length.chr + a }.join << "\x00"
    else
      # Append IP address as four 8 bit unsigned bytes
      ip.split(".").map(&:to_i).pack("C*")
    end

    # RDATA is 4 bytes
    section << [rdata.length].pack("n").b
    section << rdata.b
    section
  end

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

  def next_available_port
    udp = UDPSocket.new
    udp.bind("127.0.0.1", 0)
    udp.addr[1]
  ensure
    udp.close
  end
end
