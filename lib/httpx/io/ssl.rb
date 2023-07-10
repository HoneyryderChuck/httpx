# frozen_string_literal: true

require "openssl"

module HTTPX
  TLSError = OpenSSL::SSL::SSLError
  IPRegex = Regexp.union(Resolv::IPv4::Regex, Resolv::IPv6::Regex)

  class SSL < TCP
    using RegexpExtensions unless Regexp.method_defined?(:match?)

    TLS_OPTIONS = if OpenSSL::SSL::SSLContext.instance_methods.include?(:alpn_protocols)
      { alpn_protocols: %w[h2 http/1.1].freeze }.freeze
    else
      {}.freeze
    end

    def initialize(_, _, options)
      super
      @ctx = OpenSSL::SSL::SSLContext.new
      ctx_options = TLS_OPTIONS.merge(options.ssl)
      @sni_hostname = ctx_options.delete(:hostname) || @hostname
      @ctx.set_params(ctx_options) unless ctx_options.empty?
      @state = :negotiated if @keep_open

      @hostname_is_ip = IPRegex.match?(@sni_hostname)
    end

    def protocol
      @io.alpn_protocol || super
    rescue StandardError
      super
    end

    def can_verify_peer?
      @ctx.verify_mode == OpenSSL::SSL::VERIFY_PEER
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
    end

    def connected?
      @state == :negotiated
    end

    def connect
      super
      return if @state == :negotiated ||
                @state != :connected

      unless @io.is_a?(OpenSSL::SSL::SSLSocket)
        @io = OpenSSL::SSL::SSLSocket.new(@io, @ctx)
        @io.hostname = @sni_hostname unless @hostname_is_ip
        @io.sync_close = true
      end
      try_ssl_connect
    end

    def try_ssl_connect
      case @io.connect_nonblock(exception: false)
      when :wait_readable
        @interests = :r
        return
      when :wait_writable
        @interests = :w
        return
      end
      @io.post_connection_check(@sni_hostname) if @ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE && !@hostname_is_ip
      transition(:negotiated)
      @interests = :w
    end

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
        "Server certificate:\n " \
        "subject: #{server_cert.subject}\n " \
        "start date: #{server_cert.not_before}\n " \
        "expire date: #{server_cert.not_after}\n " \
        "issuer: #{server_cert.issuer}\n " \
        "SSL certificate verify ok."
    end
  end
end
