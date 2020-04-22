# frozen_string_literal: true

require "openssl"

module HTTPX
  class SSL < TCP
    TLS_OPTIONS = if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
      { alpn_protocols: %w[h2 http/1.1] }
    else
      # :nocov:
      {}
      # :nocov:
    end

    def initialize(_, _, options)
      @ctx = OpenSSL::SSL::SSLContext.new
      ctx_options = TLS_OPTIONS.merge(options.ssl)
      @ctx.set_params(ctx_options) unless ctx_options.empty?
      super
      @state = :negotiated if @keep_open
    end

    def interests
      @interests || super
    end

    def protocol
      @io.alpn_protocol || super
    rescue StandardError
      super
    end

    def verify_hostname(host)
      return false if @ctx.verify_mode == OpenSSL::SSL::VERIFY_NONE
      return false if !@io.respond_to?(:peer_cert) || @io.peer_cert.nil?

      OpenSSL::SSL.verify_certificate_identity(@io.peer_cert, host)
    end

    def close
      super
      # allow reconnections
      # connect only works if initial @io is a socket
      @io = @io.io if @io.respond_to?(:io)
      @negotiated = false
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

      unless @io.is_a?(OpenSSL::SSL::SSLSocket)
        @io = OpenSSL::SSL::SSLSocket.new(@io, @ctx)
        @io.hostname = @hostname
        @io.sync_close = true
      end
      @io.connect_nonblock
      @io.post_connection_check(@hostname) if @ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE
      transition(:negotiated)
    rescue ::IO::WaitReadable
      @interests = :r
    rescue ::IO::WaitWritable
      @interests = :w
    end

    # :nocov:
    if RUBY_VERSION < "2.3"
      def read(_, buffer)
        super
      rescue ::IO::WaitWritable
        buffer.clear
        0
      end

      def write(*)
        super
      rescue ::IO::WaitReadable
        0
      end
    else
      if OpenSSL::VERSION < "2.0.6"
        def read(size, buffer)
          @io.read_nonblock(size, buffer)
          buffer.bytesize
        rescue ::IO::WaitReadable,
               ::IO::WaitWritable
          buffer.clear
          0
        rescue EOFError
          nil
        end
      end
    end
    # :nocov:

    # :nocov:
    def inspect
      id = @io.closed? ? "closed" : @io.to_io.fileno
      "#<SSL(fd: #{id}): #{@ip}:#{@port} state: #{@state}>"
    end
    # :nocov:

    private

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

      server_cert = @io.peer_cert

      "#{super}\n\n" \
      "SSL connection using #{@io.ssl_version} / #{Array(@io.cipher).first}\n" \
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
