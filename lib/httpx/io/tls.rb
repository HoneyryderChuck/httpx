# frozen_string_literal: true

require "httpx/io/ruby-tls"
require "openssl"

module HTTPX
  class SSL < TCP
    def initialize(_, _, options)
      super
      @encrypted = Buffer.new(Connection::BUFFER_SIZE)
      @decrypted = "".b
      tls_options = convert_tls_options(options.ssl)
      @sni_hostname = tls_options[:host_name]
      @ctx = RubyTls::SSL::Box.new(false, self, tls_options)
      @state = :negotiated if @keep_open
    end

    def interests
      @interests || super
    end

    def protocol
      @protocol || super
    end

    def connected?
      @state == :negotiated
    end

    def connect
      super
      if @keep_open
        @state = :negotiated
        return
      end
      return if @state == :negotiated ||
                @state != :connected

      super
      @ctx.start
      @interests = :r
      read(@options.window_size, @decrypted)
    end

    # :nocov:
    def inspect
      id = @io.closed? ? "closed" : @io
      "#<TLS(fd: #{id}): #{@ip}:#{@port} state: #{@state}>"
    end
    # :nocov:

    alias_method :transport_close, :close
    def close
      transport_close
      @ctx.cleanup
    end

    def read(*, buffer)
      ret = super
      return ret if !ret || ret.zero?

      @ctx.decrypt(buffer.to_s.dup)
      buffer.replace(@decrypted)
      @decrypted.clear
      buffer.bytesize
    end

    alias_method :unencrypted_write, :write
    def write(buffer)
      @ctx.encrypt(buffer.to_s.dup)
      buffer.clear
      do_write
    end

    # TLS callback.
    #
    # buffers the encrypted +data+
    def transmit_cb(data)
      log { "TLS encrypted: #{data.bytesize} bytes" }
      log(level: 2) { data.inspect }
      @encrypted << data
      do_write
    end

    # TLS callback.
    #
    # buffers the decrypted +data+
    def dispatch_cb(data)
      log { "TLS decrypted: #{data.bytesize} bytes" }
      log(level: 2) { data.inspect }

      @decrypted << data
    end

    # TLS callback.
    #
    # signals TLS invalid status / shutdown.
    def close_cb
      log { "TLS closing" }
      transport_close
    end

    # TLS callback.
    #
    # handshake finished, passed negotiated +protocol+ (or :failed).
    #
    def handshake_cb(protocol)
      @protocol = String(protocol) unless protocol == :failed
      log { "TLS handshake completed: #{@protocol}" }
      transition(:negotiated)
    end

    # TLS callback.
    #
    # passed the peer +cert+ to be verified.
    #
    def verify_cb(cert)
      raise "Peer verification enabled, but no certificate received." if cert.nil?

      log { "TLS verifying #{cert}" }
      @peer_cert = OpenSSL::X509::Certificate.new(cert)
      # by default one doesn't verify client certificates in the server
      verify_hostname(@sni_hostname)
    end

    # copied from:
    # https://github.com/ruby/ruby/blob/8cbf2dae5aadfa5d6241b0df2bf44d55db46704f/ext/openssl/lib/openssl/ssl.rb#L395-L409
    #
    def verify_hostname(peer_cert)
      OpenSSL::SSL.verify_certificate_identity(peer_cert, @hostname)
    end

    private

    def do_write
      nwritten = 0
      until @encrypted.empty?
        siz = unencrypted_write(@encrypted)
        break unless !siz || siz.zero?

        nwritten += siz
      end
      nwritten
    end

    def convert_tls_options(ssl_options)
      options = {}
      options[:verify_peer] = !ssl_options.key?(:verify_mode) || ssl_options[:verify_mode] != OpenSSL::SSL::VERIFY_NONE
      options[:version] = ssl_options[:ssl_version] if ssl_options.key?(:ssl_version)
      # options[:private_key] = tls[:key] if tls.key?(:key)
      options[:cert_chain] = ssl_options[:cert_store] if ssl_options.key?(:cert_store)
      options[:ciphers] = ssl_options[:ciphers] if ssl_options.key?(:ciphers)
      options[:protocols] = ssl_options.fetch(:alpn_protocols, %w[h2 http/1.1])
      options[:fallback] = "http/1.1"
      options[:host_name] = ssl_options.fetch(:hostname, @hostname)
      options
    end

    def transition(nextstate)
      case nextstate
      when :negotiated
        return unless @state == :connected
      when :closed
        return unless @state == :negotiated ||
                      @state == :connected
      end
      do_transition(nextstate)
    end

    def log_transition_state(nextstate)
      return super unless nextstate == :negotiated

      server_cert = @peer_cert

      "#{super}\n\n" \
        "SSL connection using #{@ctx.ssl_version} / #{Array(@ctx.cipher).first}\n" \
        "ALPN, server accepted to use #{protocol}\n" \
        "Server certificate:\n" \
        " subject: #{server_cert.subject}\n" \
        " start date: #{server_cert.not_before}\n" \
        " expire date: #{server_cert.not_after}\n" \
        " issuer: #{server_cert.issuer}\n" \
        " SSL certificate verify ok."
    end
  end
end
