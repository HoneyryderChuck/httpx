# frozen_string_literal: true

class HTTPX::TLS
  class Context

    # Based on information from https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
    CIPHERS = "EECDH+AESGCM:EDH+AESGCM:ECDHE-RSA-AES128-GCM-SHA256:AES256+EECDH:DHE-RSA-AES128-GCM-SHA256:AES256+EDH:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4"
    SESSION = "ruby-tls"

    ALPN_LOOKUP = ::Concurrent::Map.new
    ALPN_Select_CB = FFI::Function.new(:int, [
                                         # array of str, unit8 out,uint8 in,        *arg
                                         :pointer, :pointer, :pointer, :string, :uint, :pointer
                                       ]) do |ssl_p, out, outlen, inp, inlen, _arg|
      ssl = Box::InstanceLookup[ssl_p.address]
      return SSL::SSL_TLSEXT_ERR_ALERT_FATAL unless ssl

      protos = ssl.context.alpn_str
      status = SSL.SSL_select_next_proto(out, outlen, protos, protos.length, inp, inlen)
      ssl.alpn_negotiated

      case status
      when SSL::OPENSSL_NPN_UNSUPPORTED
        SSL::SSL_TLSEXT_ERR_ALERT_FATAL
      when SSL::OPENSSL_NPN_NEGOTIATED
        SSL::SSL_TLSEXT_ERR_OK
      when SSL::OPENSSL_NPN_NO_OVERLAP
        SSL::SSL_TLSEXT_ERR_ALERT_WARNING
      end
    end

    attr_reader :is_server, :ssl_ctx, :alpn_set, :alpn_str

    def initialize(server, options = {})
      @is_server = server

      if @is_server
        @ssl_ctx = SSL.SSL_CTX_new(SSL.TLS_server_method)
        set_private_key(options[:private_key] || SSL::DEFAULT_PRIVATE)
        set_certificate(options[:cert_chain]  || SSL::DEFAULT_CERT)
        set_client_ca(options[:client_ca])
      else
        @ssl_ctx = SSL.SSL_CTX_new(SSL.TLS_client_method)
      end

      SSL.SSL_CTX_set_options(@ssl_ctx, SSL::SSL_OP_ALL)
      SSL.SSL_CTX_set_mode(@ssl_ctx, SSL::SSL_MODE_RELEASE_BUFFERS)

      SSL.SSL_CTX_set_cipher_list(@ssl_ctx, options[:ciphers] || CIPHERS)

      set_min_version(options[:version])

      if @is_server
        SSL.SSL_CTX_sess_set_cache_size(@ssl_ctx, 128)
        SSL.SSL_CTX_set_session_id_context(@ssl_ctx, SESSION, 8)
      else
        set_private_key(options[:private_key])
        set_certificate(options[:cert_chain])
      end
      set_alpn_negotiation(options[:protocols])
    end

    def cleanup
      return unless @ssl_ctx

      SSL.SSL_CTX_free(@ssl_ctx)
      @ssl_ctx = nil
    end

    def add_server_name_indication
      raise Error, "only valid for server mode context" unless @is_server

      SSL.SSL_CTX_set_tlsext_servername_callback(@ssl_ctx, ServerNameCB)
    end

    ServerNameCB = FFI::Function.new(:int, %i[pointer pointer pointer]) do |ssl, _, _|
      ruby_ssl = Box::InstanceLookup[ssl.address]
      return SSL::SSL_TLSEXT_ERR_NOACK unless ruby_ssl

      ctx = ruby_ssl.hosts[SSL.SSL_get_servername(ssl, SSL::TLSEXT_NAMETYPE_host_name)]
      if ctx
        SSL.SSL_set_SSL_CTX(ssl, ctx.ssl_ctx)
        SSL::SSL_TLSEXT_ERR_OK
      else
        SSL::SSL_TLSEXT_ERR_ALERT_FATAL
      end
    end

    private

    def self.build_alpn_string(protos)
      protos.reduce("".b) do |buffer, proto|
        buffer << proto.bytesize
        buffer << proto
      end
    end

    # Version can be one of:
    # :SSL3, :TLS1, :TLS1_1, :TLS1_2, :TLS1_3, :TLS_MAX
    if SSL::VERSION_SUPPORTED

      def set_min_version(version)
        return unless version

        num = SSL.const_get("#{version}_VERSION")
        SSL.SSL_CTX_set_min_proto_version(@ssl_ctx, num) == 1
      rescue NameError
        raise Error, "#{version} is unsupported"
      end

    else
      def set_min_version(_version); end
    end

    if SSL::ALPN_SUPPORTED
      def set_alpn_negotiation(protocols)
        @alpn_set = false
        return unless protocols

        if @is_server
          @alpn_str = Context.build_alpn_string(protocols)
          SSL.SSL_CTX_set_alpn_select_cb(@ssl_ctx, ALPN_Select_CB, nil)
          @alpn_set = true
        else
          protocols = Context.build_alpn_string(protocols)
          @alpn_set = SSL.SSL_CTX_set_alpn_protos(@ssl_ctx, protocols, protocols.length) == 0
        end
      end
    else
      def set_alpn_negotiation(_protocols); end
    end

    def set_private_key(key)
      err = if key.is_a? FFI::Pointer
        SSL.SSL_CTX_use_PrivateKey(@ssl_ctx, key)
      elsif key && File.file?(key)
        SSL.SSL_CTX_use_PrivateKey_file(@ssl_ctx, key, SSL_FILETYPE_PEM)
      else
        1
      end

      # Check for errors
      if err <= 0
        # TODO: : ERR_print_errors_fp or ERR_print_errors
        # So we can properly log the issue
        cleanup
        raise Error, "invalid private key or file not found"
      end
    end

    def set_certificate(cert)
      err = if cert.is_a? FFI::Pointer
        SSL.SSL_CTX_use_certificate(@ssl_ctx, cert)
      elsif cert && File.file?(cert)
        SSL.SSL_CTX_use_certificate_chain_file(@ssl_ctx, cert)
      else
        1
      end

      if err <= 0
        cleanup
        raise Error, "invalid certificate or file not found"
      end
    end

    def set_client_ca(ca)
      return unless ca

      if File.file?(ca) && (ca_ptr = SSL.SSL_load_client_CA_file(ca))
        # there is no error checking provided by SSL_CTX_set_client_CA_list
        SSL.SSL_CTX_set_client_CA_list(@ssl_ctx, ca_ptr)
      else
        cleanup
        raise Error, "invalid ca certificate or file not found"
      end
    end
  end
end
