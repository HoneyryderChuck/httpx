# frozen_string_literal: true

require "openssl"

module HTTPX
  TLSError = OpenSSL::SSL::SSLError

  class SSL < TCP
    # rubocop:disable Style/MutableConstant
    TLS_OPTIONS = { alpn_protocols: %w[h2 http/1.1].freeze }
    # https://github.com/jruby/jruby-openssl/issues/284
    # TODO: remove when dropping support for jruby-openssl < 0.15.4
    TLS_OPTIONS[:verify_hostname] = true if RUBY_ENGINE == "jruby" && JOpenSSL::VERSION < "0.15.4"
    # rubocop:enable Style/MutableConstant
    TLS_OPTIONS.freeze

    attr_writer :ssl_session

    def initialize(_, _, options)
      super

      ctx_options = TLS_OPTIONS.merge(options.ssl)
      @sni_hostname = ctx_options.delete(:hostname) || @hostname

      if @keep_open && @io.is_a?(OpenSSL::SSL::SSLSocket)
        # externally initiated ssl socket
        @ctx = @io.context
        @state = :negotiated
      else
        @ctx = OpenSSL::SSL::SSLContext.new
        @ctx.set_params(ctx_options) unless ctx_options.empty?
        unless @ctx.session_cache_mode.nil? # a dummy method on JRuby
          @ctx.session_cache_mode =
            OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT | OpenSSL::SSL::SSLContext::SESSION_CACHE_NO_INTERNAL_STORE
        end

        yield(self) if block_given?
      end

      @verify_hostname = @ctx.verify_hostname
    end

    if OpenSSL::SSL::SSLContext.method_defined?(:session_new_cb=)
      def session_new_cb(&pr)
        @ctx.session_new_cb = proc { |_, sess| pr.call(sess) }
      end
    else
      # session_new_cb not implemented under JRuby
      def session_new_cb; end
    end

    def protocol
      @io.alpn_protocol || super
    rescue StandardError
      super
    end

    if RUBY_ENGINE == "jruby"
      # in jruby, alpn_protocol may return ""
      # https://github.com/jruby/jruby-openssl/issues/287
      def protocol
        proto = @io.alpn_protocol

        return super if proto.nil? || proto.empty?

        proto
      rescue StandardError
        super
      end
    end

    def can_verify_peer?
      @ctx.verify_mode == OpenSSL::SSL::VERIFY_PEER
    end

    def verify_hostname(host)
      return false if @ctx.verify_mode == OpenSSL::SSL::VERIFY_NONE
      return false if !@io.respond_to?(:peer_cert) || @io.peer_cert.nil?

      OpenSSL::SSL.verify_certificate_identity(@io.peer_cert, host)
    end

    def connected?
      @state == :negotiated
    end

    def expired?
      super || ssl_session_expired?
    end

    def ssl_session_expired?
      @ssl_session.nil? || Process.clock_gettime(Process::CLOCK_REALTIME) >= (@ssl_session.time.to_f + @ssl_session.timeout)
    end

    def connect
      return if @state == :negotiated

      unless @state == :connected
        super
        return unless @state == :connected
      end

      unless @io.is_a?(OpenSSL::SSL::SSLSocket)
        if (hostname_is_ip = (@ip == @sni_hostname))
          # IPv6 address would be "[::1]", must turn to "0000:0000:0000:0000:0000:0000:0000:0001" for cert SAN check
          @sni_hostname = @ip.to_string
          # IP addresses in SNI is not valid per RFC 6066, section 3.
          @ctx.verify_hostname = false
        end

        @io = OpenSSL::SSL::SSLSocket.new(@io, @ctx)

        @io.hostname = @sni_hostname unless hostname_is_ip
        @io.session = @ssl_session unless ssl_session_expired?
        @io.sync_close = true
      end
      try_ssl_connect
    end

    def try_ssl_connect
      ret = @io.connect_nonblock(exception: false)
      log(level: 3, color: :cyan) { "TLS CONNECT: #{ret}..." }
      case ret
      when :wait_readable
        @interests = :r
        return
      when :wait_writable
        @interests = :w
        return
      end
      @io.post_connection_check(@sni_hostname) if @ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE && @verify_hostname
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
