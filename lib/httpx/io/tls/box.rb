# frozen_string_literal: true

class HTTPX::TLS
  class Box
    InstanceLookup = ::Concurrent::Map.new

    READ_BUFFER = 2048
    SSL_VERIFY_PEER = 0x01
    SSL_VERIFY_CLIENT_ONCE = 0x04

    VerifyCB = FFI::Function.new(:int, %i[int pointer]) do |preverify_ok, x509_store|
      x509 = SSL.X509_STORE_CTX_get_current_cert(x509_store)
      ssl = SSL.X509_STORE_CTX_get_ex_data(x509_store, SSL.SSL_get_ex_data_X509_STORE_CTX_idx)

      bio_out = SSL.BIO_new(SSL.BIO_s_mem)
      ret = SSL.PEM_write_bio_X509(bio_out, x509)
      if ret
        len = SSL.BIO_pending(bio_out)
        buffer = FFI::MemoryPointer.new(:char, len, false)
        size = SSL.BIO_read(bio_out, buffer, len)

        # THis is the callback into the ruby class
        cert = buffer.read_string(size)
        SSL.BIO_free(bio_out)
        # InstanceLookup[ssl.address].verify(cert) || preverify_ok.zero? ? 1 : 0
        depth = SSL.X509_STORE_CTX_get_error_depth(ssl)
        box = InstanceLookup[ssl.address]
        if preverify_ok == 1

          hostname_verify = box.verify(cert)
          if hostname_verify
            1
          else
            # SSL.X509_STORE_CTX_set_error(x509_store, SSL::X509_V_ERR_HOSTNAME_MISMATCH)
            0
          end
        else
          1
        end
      else
        SSL.BIO_free(bio_out)
        SSL.X509_STORE_CTX_set_error(x509_store, SSL::X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT)
        0
      end
    end

    attr_reader :is_server, :context, :handshake_completed, :hosts, :ssl_version, :cipher, :verify_peer

    def initialize(is_server, transport, options = {})
      @ready = true

      @handshake_completed = false
      @handshake_signaled = false
      @alpn_negotiated = false
      @transport = transport

      @read_buffer = FFI::MemoryPointer.new(:char, READ_BUFFER, false)

      @is_server = is_server
      @context = Context.new(is_server, options)

      @bioRead = SSL.BIO_new(SSL.BIO_s_mem)
      @bioWrite = SSL.BIO_new(SSL.BIO_s_mem)
      @ssl = SSL.SSL_new(@context.ssl_ctx)
      SSL.SSL_set_bio(@ssl, @bioRead, @bioWrite)

      @write_queue = []

      InstanceLookup[@ssl.address] = self

      @verify_peer = options[:verify_peer]
      
      if @verify_peer
        SSL.SSL_set_verify(@ssl, SSL_VERIFY_PEER | SSL_VERIFY_CLIENT_ONCE, VerifyCB)
      end

      # Add Server Name Indication (SNI) for client connections
      if (hostname = options[:hostname])
        if is_server
          @hosts = ::Concurrent::Map.new
          @hosts[hostname.to_s] = @context
          @context.add_server_name_indication
        else
          SSL.SSL_set_tlsext_host_name(@ssl, hostname)
        end
      end

      SSL.SSL_connect(@ssl) unless is_server
    end

    def add_host(hostname:, **options)
      raise Error, "Server Name Indication (SNI) not configured for default host" unless @hosts
      raise Error, "only valid for server mode context" unless @is_server

      context = Context.new(true, options)
      @hosts[hostname.to_s] = context
      context.add_server_name_indication
      nil
    end

    # Careful with this.
    # If you remove all the hosts you'll end up with a segfault
    def remove_host(hostname)
      raise Error, "Server Name Indication (SNI) not configured for default host" unless @hosts
      raise Error, "only valid for server mode context" unless @is_server

      context = @hosts[hostname.to_s]
      if context
        @hosts.delete(hostname.to_s)
        context.cleanup
      end
      nil
    end

    def get_peer_cert
      return "" unless @ready

      SSL.SSL_get_peer_certificate(@ssl)
    end

    def start
      return unless @ready

      dispatch_cipher_text
    end

    def encrypt(data)
      return unless @ready

      wrote = put_plain_text data
      if wrote < 0
        @transport.close_cb
      else
        dispatch_cipher_text
      end
    end

    SSL_ERROR_WANT_READ = 2
    SSL_ERROR_SSL = 1
    def decrypt(data)
      return unless @ready

      put_cipher_text data

      unless SSL.is_init_finished(@ssl)
        resp = @is_server ? SSL.SSL_accept(@ssl) : SSL.SSL_connect(@ssl)

        if resp < 0
          err_code = SSL.SSL_get_error(@ssl, resp)
          if err_code != SSL_ERROR_WANT_READ
            if err_code == SSL_ERROR_SSL
              verify_msg = SSL.X509_verify_cert_error_string(SSL.SSL_get_verify_result(@ssl))
              @transport.close_cb(verify_msg)
            end
            return
          end
        end

        @handshake_completed = true
        @ssl_version = SSL.get_version(@ssl)
        @cipher = SSL.get_current_cipher(@ssl)
        signal_handshake unless @handshake_signaled
      end

      loop do
        size = get_plain_text(@read_buffer, READ_BUFFER)
        if size > 0
          @transport.dispatch_cb @read_buffer.read_string(size)
        else
          break
        end
      end

      dispatch_cipher_text
    end

    def signal_handshake
      @handshake_signaled = true

      # Check protocol support here
      if @context.alpn_set
        proto = alpn_negotiated_protocol

        if proto == :failed
          if @alpn_negotiated
            # We should shutdown if this is the case
            # TODO: send back proper error message
            @transport.close_cb
            return
          end
        end
        @transport.alpn_protocol_cb(proto)
      end

      @transport.handshake_cb
    end

    def alpn_negotiated!
      @alpn_negotiated = true
    end

    SSL_RECEIVED_SHUTDOWN = 2
    def cleanup
      return unless @ready

      @ready = false

      InstanceLookup.delete @ssl.address

      if (SSL.SSL_get_shutdown(@ssl) & SSL_RECEIVED_SHUTDOWN) != 0
        SSL.SSL_shutdown @ssl
      else
        SSL.SSL_clear @ssl
      end

      SSL.SSL_free @ssl

      if @hosts
        @hosts.each_value(&:cleanup)
        @hosts = nil
      else
        @context.cleanup
      end
    end

    # Called from class level callback function
    def verify(cert)
      @transport.verify_cb(cert)
    end

    def close(msg)
      @transport.close_cb(msg)
    end

    private

    def alpn_negotiated_protocol
      return nil unless @context.alpn_set

      proto = FFI::MemoryPointer.new(:pointer, 1, true)
      len = FFI::MemoryPointer.new(:uint, 1, true)
      SSL.SSL_get0_alpn_selected(@ssl, proto, len)

      resp = proto.get_pointer(0)

      return :failed if resp.address == 0

      length = len.get_uint(0)
      resp.read_string(length)
    end

    def get_plain_text(buffer, ready)
      # Read the buffered clear text
      size = SSL.SSL_read(@ssl, buffer, ready)
      if size >= 0
        size
      else
        SSL.SSL_get_error(@ssl, size) == SSL_ERROR_WANT_READ ? 0 : -1
      end
    end

    def pending_data(bio)
      SSL.BIO_pending(bio)
    end

    def get_cipher_text(buffer, length)
      SSL.BIO_read(@bioWrite, buffer, length)
    end

    def put_cipher_text(data)
      len = data.bytesize
      wrote = SSL.BIO_write(@bioRead, data, len)
      wrote == len
    end

    SSL_ERROR_WANT_WRITE = 3
    def put_plain_text(data)
      @write_queue.push(data) if data
      return 0 unless SSL.is_init_finished(@ssl)

      fatal = false
      did_work = false

      until @write_queue.empty?
        data = @write_queue.pop
        len = data.bytesize

        wrote = SSL.SSL_write(@ssl, data, len)

        if wrote > 0
          did_work = true
        else
          err_code = SSL.SSL_get_error(@ssl, wrote)
          if (err_code != SSL_ERROR_WANT_READ) && (err_code != SSL_ERROR_WANT_WRITE)
            fatal = true
          else
            # Not fatal - add back to the queue
            @write_queue.unshift data
          end

          break
        end
      end

      if did_work
        1
      elsif fatal
        -1
      else
        0
      end
    end

    CIPHER_DISPATCH_FAILED = "Cipher text dispatch failed"
    def dispatch_cipher_text
      loop do
        did_work = false

        # Get all the encrypted data and transmit it
        pending = pending_data(@bioWrite)
        if pending > 0
          buffer = FFI::MemoryPointer.new(:char, pending, false)

          resp = get_cipher_text(buffer, pending)
          raise Error, CIPHER_DISPATCH_FAILED unless resp > 0

          @transport.transmit_cb(buffer.read_string(resp))
          did_work = true
        end

        # Send any queued out going data
        unless @write_queue.empty?
          resp = put_plain_text nil
          if resp > 0
            did_work = true
          elsif resp < 0
            @transport.close_cb
          end
        end
        break unless did_work
      end
    end
  end
end