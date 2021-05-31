# frozen_string_literal: true

class SettingsTimeoutServer
  attr_reader :origin, :frames

  def initialize
    @port = 0
    @host = "localhost"
    @frames = []

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
    sock = @server.accept

    conn = HTTP2Next::Server.new
    conn.on(:frame_received) do |frame|
      @frames << frame
    end
    conn.on(:goaway) do
      sock.close
    end

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
