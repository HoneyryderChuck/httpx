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

  def initialize(tls: true, alpn_protocols: %w[h2])
    @port = 0
    @host = "localhost"

    @ios = []
    @conns = {}
    @server = TCPServer.new(0)
    @is_tls = tls

    if tls
      @origin = "https://localhost:#{@server.addr[1]}"

      ctx = OpenSSL::SSL::SSLContext.new

      certs_dir = File.expand_path(File.join("..", "..", "ci", "certs"), __FILE__)

      ctx.ca_file = File.join(certs_dir, "ca-bundle.crt")
      ctx.cert = OpenSSL::X509::Certificate.new(File.read(File.join(certs_dir, "server.crt")))
      ctx.key = OpenSSL::PKey.read(File.read(File.join(certs_dir, "server.key")))

      ctx.ssl_version = :TLSv1_2
      ctx.alpn_protocols = alpn_protocols

      ctx.alpn_select_cb = lambda do |protocols|
        raise "Protocol h2 is required" if (alpn_protocols & protocols).empty?

        protocols.first
      end

      @server = OpenSSL::SSL::SSLServer.new(@server, ctx)
      @server.singleton_class.attr_reader :ctx
    else
      @origin = "http://localhost:#{@server.addr[1]}"
    end
  end

  def shutdown
    @server.close
  end

  def start
    begin
      loop do
        ios, * = IO.select([@server, *@ios])

        return unless ios

        handle_ios(ios)
      end
    rescue IOError, SystemCallError
    end
  end

  private

  def handle_ios(ios)
    ios.each do |io|
      case io
      when TCPServer, OpenSSL::SSL::SSLServer
        handle_server(io)
      else
        handle_socket(io)
      end
    end
  end

  def handle_server(server)
    loop do
      case (sock = server.to_io.accept_nonblock(exception: false))
      when :wait_readable
        return
      when nil
        raise EOFError
      else
        if @is_tls
          sock = OpenSSL::SSL::SSLSocket.new(sock, server.ctx)
          sock.sync_close = true
          sock.accept
        end

        @ios << sock

        conn = ::HTTP2::Server.new
        handle_connection(conn, sock)

        @conns[sock] = conn
      end
    end
  rescue StandardError => e
    warn "#{e.class} exception: #{e.message} - closing server."
    warn e.backtrace
  end

  def handle_socket(sock)
    loop do
      case (data = sock.read_nonblock(1024, exception: false))
      when :wait_readable
        return
      when nil
        close_socket(sock)
        return
      else
        buffer_to_socket(sock, data)

        if sock.closed?
          purge_socket(sock)
          return
        end
      end
    end
  rescue StandardError => e
    puts "#{e.class} exception: #{e.message} - closing socket."
    puts e.backtrace
    close_socket(sock)
  end

  def buffer_to_socket(sock, data)
    @conns[sock] << data
  end

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
      close_socket(sock)
    end
    conn.on(:stream) do |stream|
      handle_stream(conn, stream)
    end
  end

  def close_socket(sock)
    sock.close
    purge_socket(sock)
  end

  def purge_socket(sock)
    @ios.delete(sock)
    @conns.delete(sock)
  end
end

class TestDNSResolver
  attr_reader :queries, :answers

  def initialize(port = next_available_port, socket_type = :udp, ttl: 120)
    @port = port
    @can_log = ENV.key?("HTTPX_DEBUG")
    @queries = 0
    @answers = 0
    @socket_type = socket_type
    @ttl = ttl
  end

  def nameserver
    ["127.0.0.1", @port]
  end

  def start
    if @socket_type == :udp
      Socket.udp_server_loop(@port) do |query, src|
        @queries += 1
        answer = dns_response(query)
        next unless answer

        src.reply(answer)
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
            next unless answer

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
    typevalue = extract_family(query)
    ips = resolve(domain, typevalue)

    response = response_header(query)
    response << question_section(query)
    response << answer_section(ips)
    response
  rescue Resolv::ResolvError
    # nxdomain error
    response = response_header(query, 3)
    response << question_section(query)
    response
  end

  def resolve(domain, typevalue)
    Resolv.getaddresses(domain).filter_map do |address|
      begin
        ip = IPAddr.new(address)

        address if case typevalue
                   when 1
                     ip.ipv4?
                   when 28
                     ip.ipv6?
                   else
                     false
                   end
      rescue IPAddr::AddressFamilyError
        # CNAME
        address
      end
    end
  end

  def response_header(query, rccode = 0)
    rc = [rccode].pack("C")
    qdcount = "\x00\x01".b
    ancount = rccode.positive? ? "\x00\x00".b : "\x00\x01".b
    "#{query[0, 2]}\x81#{rc}#{qdcount}#{ancount}\x00\x00\x00\x00".b
  end

  def question_section(query)
    # Append original question section
    section = query[12..-1].b

    # Use pointer to refer to domain name in question section
    section << "\xc0\x0c".b

    section
  end

  def answer_section(ips)
    section = "".b

    ips.each do |ip|
      begin
        ip = IPAddr.new(ip)
      rescue IPAddr::InvalidAddressError
        cname = ip
      end

      # Set response type accordingly
      section = if cname
        "\x00\x05".b
      else
        ip.ipv6? ? "\x00\x1C".b : "\x00\x01".b
      end

      # Set response class (IN)
      section << "\x00\x01".b

      # TTL in seconds
      section << [@ttl].pack("N").b

      # Calculate RDATA - we need its length in advance
      rdata = if cname
        ip.split(".").map { |a| a.length.chr + a }.join << "\x00"
      else
        # Append IP address as four 8 bit unsigned bytes
        ip.hton
      end

      # RDATA is 4 bytes
      section << [rdata.length].pack("n").b
      section << rdata.b
    end
    section
  end

  def extract_family(query)
    section = query[12..-1].b
    flags = section[-4..-1].b
    flags.unpack1("n")
  end

  def extract_domain(query)
    domain = +""

    # Check "Opcode" of question header for valid question
    if (query[2].ord & 120).zero?
      # Read QNAME section of question section
      # DNS header section is 12 bytes long, so data starts at offset 12

      idx = 12
      len = query[idx].ord
      # Strings are rendered as a byte containing length, then text.. repeat until length of 0
      until len.zero?
        domain << "#{query[idx + 1, len]}."
        idx += len + 1
        len = query[idx].ord
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
