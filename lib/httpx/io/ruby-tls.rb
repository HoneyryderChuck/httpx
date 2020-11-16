# frozen_string_literal: true

require "ffi"
require "ffi-compiler/loader"
require "concurrent"

# Copyright (c) 2004-2013 Cotag Media
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is furnished
# to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# ===
#
# This license applies to all parts of uvrb (Ruby FFI bindings for libuv only)
# Libuv itself [is using Node license](https://github.com/joyent/libuv/blob/master/LICENSE)

module RubyTls
  module SSL
    extend FFI::Library

    if FFI::Platform.windows?
      begin
        ffi_lib "libeay32", "ssleay32"
      rescue LoadError
        ffi_lib "libcrypto-1_1-x64", "libssl-1_1-x64"
      end
    else
      ffi_lib "ssl"
    end

    # Common structures
    typedef :pointer, :user_data
    typedef :pointer, :bio
    typedef :pointer, :evp_key
    typedef :pointer, :evp_key_pointer
    typedef :pointer, :x509
    typedef :pointer, :x509_pointer
    typedef :pointer, :ssl
    typedef :pointer, :cipher
    typedef :pointer, :ssl_ctx
    typedef :int, :buffer_length
    typedef :int, :pass_length
    typedef :int, :read_write_flag

    SSL_ST_OK = 0x03
    begin
      attach_function :SSL_library_init, [], :int
      attach_function :SSL_load_error_strings, [], :void
      attach_function :ERR_load_crypto_strings, [], :void

      attach_function :SSL_state, [:ssl], :int
      def self.is_init_finished(ssl)
        SSL_state(ssl) == SSL_ST_OK
      end

      OPENSSL_V1_1 = false
    rescue FFI::NotFoundError
      OPENSSL_V1_1 = true
      OPENSSL_INIT_LOAD_SSL_STRINGS = 0x200000
      OPENSSL_INIT_NO_LOAD_SSL_STRINGS = 0x100000
      attach_function :OPENSSL_init_ssl, %i[uint64 pointer], :int

      attach_function :SSL_get_state, [:ssl], :int
      attach_function :SSL_is_init_finished, [:ssl], :bool

      def self.is_init_finished(ssl)
        SSL_is_init_finished(ssl)
      end
    end

    # Multi-threaded support
    # callback :locking_cb, [:int, :int, :string, :int], :void
    # callback :thread_id_cb, [], :ulong
    # attach_function :CRYPTO_num_locks, [], :int
    # attach_function :CRYPTO_set_locking_callback, [:locking_cb], :void
    # attach_function :CRYPTO_set_id_callback, [:thread_id_cb], :void

    # InitializeDefaultCredentials
    attach_function :BIO_new_mem_buf, %i[string buffer_length], :bio
    attach_function :EVP_PKEY_free, [:evp_key], :void

    callback :pem_password_cb, %i[pointer buffer_length read_write_flag user_data], :pass_length
    attach_function :PEM_read_bio_PrivateKey, %i[bio evp_key_pointer pem_password_cb user_data], :evp_key

    attach_function :X509_free, [:x509], :void
    attach_function :PEM_read_bio_X509, %i[bio x509_pointer pem_password_cb user_data], :x509

    attach_function :BIO_free, [:bio], :int

    # GetPeerCert
    attach_function :SSL_get_peer_certificate, [:ssl], :x509

    # PutPlaintext
    attach_function :SSL_write, %i[ssl buffer_in buffer_length], :int
    attach_function :SSL_get_error, %i[ssl int], :int

    # GetCiphertext
    attach_function :BIO_read, %i[bio buffer_out buffer_length], :int

    # CanGetCiphertext
    attach_function :BIO_ctrl, %i[bio int long pointer], :long
    BIO_CTRL_PENDING = 10 # opt - is their more data buffered?
    def self.BIO_pending(bio)
      BIO_ctrl(bio, BIO_CTRL_PENDING, 0, nil)
    end

    # GetPlaintext
    attach_function :SSL_accept, [:ssl], :int
    attach_function :SSL_read, %i[ssl buffer_out buffer_length], :int
    attach_function :SSL_pending, [:ssl], :int

    # PutCiphertext
    attach_function :BIO_write, %i[bio buffer_in buffer_length], :int

    # Deconstructor
    attach_function :SSL_get_shutdown, [:ssl], :int
    attach_function :SSL_shutdown, [:ssl], :int
    attach_function :SSL_clear, [:ssl], :void
    attach_function :SSL_free, [:ssl], :void

    # Constructor
    attach_function :BIO_s_mem, [], :pointer
    attach_function :BIO_new, [:pointer], :bio
    attach_function :SSL_new, [:ssl_ctx], :ssl
    # r,   w
    attach_function :SSL_set_bio, %i[ssl bio bio], :void

    attach_function :SSL_set_ex_data, %i[ssl int string], :int
    callback :verify_callback, %i[int x509], :int
    attach_function :SSL_set_verify, %i[ssl int verify_callback], :void
    attach_function :SSL_get_verify_result, %i[ssl], :long
    attach_function :SSL_connect, [:ssl], :int

    # Verify callback
    attach_function :X509_STORE_CTX_get_current_cert, [:pointer], :x509
    attach_function :SSL_get_ex_data_X509_STORE_CTX_idx, [], :int
    attach_function :X509_STORE_CTX_get_ex_data, %i[pointer int], :ssl
    attach_function :X509_STORE_CTX_get_error_depth, %i[x509], :int
    attach_function :PEM_write_bio_X509, %i[bio x509], :bool
    attach_function :X509_verify_cert_error_string, %i[long], :string

    # SSL Context Class
    # OpenSSL before 1.1.0 do not have these methods
    # https://www.openssl.org/docs/man1.1.0/ssl/TLSv1_2_server_method.html
    begin
      attach_function :TLS_server_method, [], :pointer
      attach_function :TLS_client_method, [], :pointer
    rescue FFI::NotFoundError
      attach_function :SSLv23_server_method, [], :pointer
      attach_function :SSLv23_client_method, [], :pointer

      def self.TLS_server_method
        self.SSLv23_server_method
      end

      def self.TLS_client_method
        self.SSLv23_client_method
      end
    end

    # Version can be one of:
    # :SSL3, :TLS1, :TLS1_1, :TLS1_2, :TLS1_3, :TLS_MAX
    begin
      attach_function :SSL_get_version, %i[ssl], :string
      attach_function :SSL_get_current_cipher, %i[ssl], :cipher
      attach_function :SSL_CIPHER_get_name, %i[cipher], :string
      attach_function :SSL_CTX_set_min_proto_version, %i[ssl_ctx int], :int
      attach_function :SSL_CTX_set_max_proto_version, %i[ssl_ctx int], :int

      VERSION_SUPPORTED = true

      SSL3_VERSION    = 0x0300
      TLS1_VERSION    = 0x0301
      TLS1_1_VERSION  = 0x0302
      TLS1_2_VERSION  = 0x0303
      TLS1_3_VERSION  = 0x0304
      TLS_MAX_VERSION = TLS1_3_VERSION
      ANY_VERSION     = 0
    rescue FFI::NotFoundError
      VERSION_SUPPORTED = false
    end

    def self.get_version(ssl)
      SSL_get_version(ssl)
    end

    def self.get_current_cipher(ssl)
      cipher = SSL_get_current_cipher(ssl)
      SSL_CIPHER_get_name(cipher)
    end

    attach_function :SSL_CTX_new, [:pointer], :ssl_ctx

    attach_function :SSL_CTX_ctrl, %i[ssl_ctx int ulong pointer], :long
    SSL_CTRL_OPTIONS = 32
    def self.SSL_CTX_set_options(ssl_ctx, op)
      SSL_CTX_ctrl(ssl_ctx, SSL_CTRL_OPTIONS, op, nil)
    end
    SSL_CTRL_MODE = 33
    def self.SSL_CTX_set_mode(ssl_ctx, op)
      SSL_CTX_ctrl(ssl_ctx, SSL_CTRL_MODE, op, nil)
    end
    SSL_CTRL_SET_SESS_CACHE_SIZE = 42
    def self.SSL_CTX_sess_set_cache_size(ssl_ctx, op)
      SSL_CTX_ctrl(ssl_ctx, SSL_CTRL_SET_SESS_CACHE_SIZE, op, nil)
    end

    attach_function :SSL_ctrl, %i[ssl int long pointer], :long
    SSL_CTRL_SET_TLSEXT_HOSTNAME = 55

    def self.SSL_set_tlsext_host_name(ssl, host_name)
      name_ptr = FFI::MemoryPointer.from_string(host_name)
      raise "error setting SNI hostname" if SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, name_ptr) == 0
    end

    # Server Name Indication (SNI) Support
    # NOTE:: We've hard coded the callback here (SSL defines a NULL callback)
    callback :ssl_servername_cb, %i[ssl pointer pointer], :int
    attach_function :SSL_CTX_callback_ctrl, %i[ssl_ctx int ssl_servername_cb], :long
    SSL_CTRL_SET_TLSEXT_SERVERNAME_CB = 53
    def self.SSL_CTX_set_tlsext_servername_callback(ctx, callback)
      SSL_CTX_callback_ctrl(ctx, SSL_CTRL_SET_TLSEXT_SERVERNAME_CB, callback)
    end

    attach_function :SSL_get_servername, %i[ssl int], :string
    TLSEXT_NAMETYPE_host_name = 0

    attach_function :SSL_set_SSL_CTX, %i[ssl ssl_ctx], :ssl_ctx

    SSL_TLSEXT_ERR_OK = 0
    SSL_TLSEXT_ERR_ALERT_WARNING = 1
    SSL_TLSEXT_ERR_ALERT_FATAL = 2
    SSL_TLSEXT_ERR_NOACK = 3

    attach_function :SSL_CTX_use_PrivateKey_file, %i[ssl_ctx string int], :int, :blocking => true
    attach_function :SSL_CTX_use_PrivateKey, %i[ssl_ctx pointer], :int
    attach_function :ERR_print_errors_fp, [:pointer], :void # Pointer == File Handle
    attach_function :SSL_CTX_use_certificate_chain_file, %i[ssl_ctx string], :int, :blocking => true
    attach_function :SSL_CTX_use_certificate, %i[ssl_ctx x509], :int
    attach_function :SSL_CTX_set_cipher_list, %i[ssl_ctx string], :int
    attach_function :SSL_CTX_set_session_id_context, %i[ssl_ctx string buffer_length], :int
    attach_function :SSL_load_client_CA_file, [:string], :pointer
    attach_function :SSL_CTX_set_client_CA_list, %i[ssl_ctx pointer], :void
    attach_function :SSL_CTX_load_verify_locations, %i[ssl_ctx pointer], :int, :blocking => true

    # OpenSSL before 1.0.2 do not have these methods
    begin
      attach_function :SSL_CTX_set_alpn_protos, %i[ssl_ctx string uint], :int

      OPENSSL_NPN_UNSUPPORTED = 0
      OPENSSL_NPN_NEGOTIATED = 1
      OPENSSL_NPN_NO_OVERLAP = 2

      attach_function :SSL_select_next_proto, %i[pointer pointer string uint string uint], :int

      # array of str, unit8 out,uint8 in,        *arg
      callback :alpn_select_cb, %i[ssl pointer pointer string uint pointer], :int
      attach_function :SSL_CTX_set_alpn_select_cb, %i[ssl_ctx alpn_select_cb pointer], :void

      attach_function :SSL_get0_alpn_selected, %i[ssl pointer pointer], :void
      ALPN_SUPPORTED = true
  rescue FFI::NotFoundError
    ALPN_SUPPORTED = false
    end

    # Deconstructor
    attach_function :SSL_CTX_free, [:ssl_ctx], :void

    PrivateMaterials = <<~keystr
      -----BEGIN RSA PRIVATE KEY-----
      MIICXAIBAAKBgQDCYYhcw6cGRbhBVShKmbWm7UVsEoBnUf0cCh8AX+MKhMxwVDWV
      Igdskntn3cSJjRtmgVJHIK0lpb/FYHQB93Ohpd9/Z18pDmovfFF9nDbFF0t39hJ/
      AqSzFB3GiVPoFFZJEE1vJqh+3jzsSF5K56bZ6azz38VlZgXeSozNW5bXkQIDAQAB
      AoGALA89gIFcr6BIBo8N5fL3aNHpZXjAICtGav+kTUpuxSiaym9cAeTHuAVv8Xgk
      H2Wbq11uz+6JMLpkQJH/WZ7EV59DPOicXrp0Imr73F3EXBfR7t2EQDYHPMthOA1D
      I9EtCzvV608Ze90hiJ7E3guGrGppZfJ+eUWCPgy8CZH1vRECQQDv67rwV/oU1aDo
      6/+d5nqjeW6mWkGqTnUU96jXap8EIw6B+0cUKskwx6mHJv+tEMM2748ZY7b0yBlg
      w4KDghbFAkEAz2h8PjSJG55LwqmXih1RONSgdN9hjB12LwXL1CaDh7/lkEhq0PlK
      PCAUwQSdM17Sl0Xxm2CZiekTSlwmHrtqXQJAF3+8QJwtV2sRJp8u2zVe37IeH1cJ
      xXeHyjTzqZ2803fnjN2iuZvzNr7noOA1/Kp+pFvUZUU5/0G2Ep8zolPUjQJAFA7k
      xRdLkzIx3XeNQjwnmLlncyYPRv+qaE3FMpUu7zftuZBnVCJnvXzUxP3vPgKTlzGa
      dg5XivDRfsV+okY5uQJBAMV4FesUuLQVEKb6lMs7rzZwpeGQhFDRfywJzfom2TLn
      2RdJQQ3dcgnhdVDgt5o1qkmsqQh8uJrJ9SdyLIaZQIc=
      -----END RSA PRIVATE KEY-----
      -----BEGIN CERTIFICATE-----
      MIID6TCCA1KgAwIBAgIJANm4W/Tzs+s+MA0GCSqGSIb3DQEBBQUAMIGqMQswCQYD
      VQQGEwJVUzERMA8GA1UECBMITmV3IFlvcmsxETAPBgNVBAcTCE5ldyBZb3JrMRYw
      FAYDVQQKEw1TdGVhbWhlYXQubmV0MRQwEgYDVQQLEwtFbmdpbmVlcmluZzEdMBsG
      A1UEAxMUb3BlbmNhLnN0ZWFtaGVhdC5uZXQxKDAmBgkqhkiG9w0BCQEWGWVuZ2lu
      ZWVyaW5nQHN0ZWFtaGVhdC5uZXQwHhcNMDYwNTA1MTcwNjAzWhcNMjQwMjIwMTcw
      NjAzWjCBqjELMAkGA1UEBhMCVVMxETAPBgNVBAgTCE5ldyBZb3JrMREwDwYDVQQH
      EwhOZXcgWW9yazEWMBQGA1UEChMNU3RlYW1oZWF0Lm5ldDEUMBIGA1UECxMLRW5n
      aW5lZXJpbmcxHTAbBgNVBAMTFG9wZW5jYS5zdGVhbWhlYXQubmV0MSgwJgYJKoZI
      hvcNAQkBFhllbmdpbmVlcmluZ0BzdGVhbWhlYXQubmV0MIGfMA0GCSqGSIb3DQEB
      AQUAA4GNADCBiQKBgQDCYYhcw6cGRbhBVShKmbWm7UVsEoBnUf0cCh8AX+MKhMxw
      VDWVIgdskntn3cSJjRtmgVJHIK0lpb/FYHQB93Ohpd9/Z18pDmovfFF9nDbFF0t3
      9hJ/AqSzFB3GiVPoFFZJEE1vJqh+3jzsSF5K56bZ6azz38VlZgXeSozNW5bXkQID
      AQABo4IBEzCCAQ8wHQYDVR0OBBYEFPJvPd1Fcmd8o/Tm88r+NjYPICCkMIHfBgNV
      HSMEgdcwgdSAFPJvPd1Fcmd8o/Tm88r+NjYPICCkoYGwpIGtMIGqMQswCQYDVQQG
      EwJVUzERMA8GA1UECBMITmV3IFlvcmsxETAPBgNVBAcTCE5ldyBZb3JrMRYwFAYD
      VQQKEw1TdGVhbWhlYXQubmV0MRQwEgYDVQQLEwtFbmdpbmVlcmluZzEdMBsGA1UE
      AxMUb3BlbmNhLnN0ZWFtaGVhdC5uZXQxKDAmBgkqhkiG9w0BCQEWGWVuZ2luZWVy
      aW5nQHN0ZWFtaGVhdC5uZXSCCQDZuFv087PrPjAMBgNVHRMEBTADAQH/MA0GCSqG
      SIb3DQEBBQUAA4GBAC1CXey/4UoLgJiwcEMDxOvW74plks23090iziFIlGgcIhk0
      Df6hTAs7H3MWww62ddvR8l07AWfSzSP5L6mDsbvq7EmQsmPODwb6C+i2aF3EDL8j
      uw73m4YIGI0Zw2XdBpiOGkx2H56Kya6mJJe/5XORZedh1wpI7zki01tHYbcy
      -----END CERTIFICATE-----
    keystr

    BuiltinPasswdCB = FFI::Function.new(:int, %i[pointer int int pointer]) do |buffer, _len, _flag, _data|
      buffer.write_string("kittycat")
      8
    end

    # Locking isn't provided as long as all writes are done on the same thread.
    # This is my main use case. Happy to enable it if someone requires it and can
    # get it to work on MRI Ruby (Currently only works on JRuby and Rubinius)
    # as MRI callbacks occur on a thread pool?

    # CRYPTO_LOCK = 0x1
    # LockingCB = FFI::Function.new(:void, [:int, :int, :string, :int]) do |mode, type, file, line|
    #    if (mode & CRYPTO_LOCK) != 0
    #        SSL_LOCKS[type].lock
    #    else
    # Unlock a lock
    #        SSL_LOCKS[type].unlock
    #    end
    # end
    # ThreadIdCB = FFI::Function.new(:ulong, []) do
    #    Thread.current.object_id
    # end

    # INIT CODE
    @init_required ||= false
    unless @init_required
      if OPENSSL_V1_1
        self.OPENSSL_init_ssl(OPENSSL_INIT_LOAD_SSL_STRINGS, ::FFI::Pointer::NULL)
      else
        self.SSL_load_error_strings
        self.SSL_library_init
        self.ERR_load_crypto_strings
      end

      # Setup multi-threaded support
      # SSL_LOCKS = []
      # num_locks = self.CRYPTO_num_locks
      # num_locks.times { SSL_LOCKS << Mutex.new }

      # self.CRYPTO_set_locking_callback(LockingCB)
      # self.CRYPTO_set_id_callback(ThreadIdCB)

      bio = self.BIO_new_mem_buf(PrivateMaterials, PrivateMaterials.bytesize)

      # Get the private key structure
      pointer = FFI::MemoryPointer.new(:pointer)
      self.PEM_read_bio_PrivateKey(bio, pointer, BuiltinPasswdCB, nil)
      DEFAULT_PRIVATE = pointer.get_pointer(0)

      # Get the certificate structure
      pointer = FFI::MemoryPointer.new(:pointer)
      self.PEM_read_bio_X509(bio, pointer, nil, nil)
      DEFAULT_CERT = pointer.get_pointer(0)

      self.BIO_free(bio)

      @init_required = true
    end

    #  Save RAM by releasing read and write buffers when they're empty
    SSL_MODE_RELEASE_BUFFERS = 0x00000010
    SSL_OP_ALL = 0x80000BFF
    SSL_FILETYPE_PEM = 1

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
        ssl.negotiated

        case status
        when SSL::OPENSSL_NPN_UNSUPPORTED
          SSL::SSL_TLSEXT_ERR_ALERT_FATAL
        when SSL::OPENSSL_NPN_NEGOTIATED
          SSL::SSL_TLSEXT_ERR_OK
        when SSL::OPENSSL_NPN_NO_OVERLAP
          SSL::SSL_TLSEXT_ERR_ALERT_WARNING
        end
      end

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
        @alpn_set = false

        version = options[:version]
        if version
          vresult = set_min_proto_version(version)
          raise "#{version} is unsupported" unless vresult
        end

        if @is_server
          SSL.SSL_CTX_sess_set_cache_size(@ssl_ctx, 128)
          SSL.SSL_CTX_set_session_id_context(@ssl_ctx, SESSION, 8)

          if SSL::ALPN_SUPPORTED && options[:protocols]
            @alpn_str = Context.build_alpn_string(options[:protocols])
            SSL.SSL_CTX_set_alpn_select_cb(@ssl_ctx, ALPN_Select_CB, nil)
            @alpn_set = true
          end
        else
          set_private_key(options[:private_key])
          set_certificate(options[:cert_chain])

          # Check for ALPN support
          if SSL::ALPN_SUPPORTED && options[:protocols]
            protocols = Context.build_alpn_string(options[:protocols])
            @alpn_set = SSL.SSL_CTX_set_alpn_protos(@ssl_ctx, protocols, protocols.length) == 0
          end
        end
      end

      # Version can be one of:
      # :SSL3, :TLS1, :TLS1_1, :TLS1_2, :TLS1_3, :TLS_MAX
      if SSL::VERSION_SUPPORTED
        def set_min_proto_version(version)
          num = SSL.const_get("#{version}_VERSION")
          SSL.SSL_CTX_set_min_proto_version(@ssl_ctx, num) == 1
        rescue NameError
          false
        end

        def set_max_proto_version(version)
          num = SSL.const_get("#{version}_VERSION")
          SSL.SSL_CTX_set_max_proto_version(@ssl_ctx, num) == 1
        rescue NameError
          false
        end
      else
        def set_min_proto_version(_version)
          false
        end

        def set_max_proto_version(_version)
          false
        end
      end

      def cleanup
        if @ssl_ctx
          SSL.SSL_CTX_free(@ssl_ctx)
          @ssl_ctx = nil
        end
      end

      attr_reader :is_server, :ssl_ctx, :alpn_set, :alpn_str

      def add_server_name_indication
        raise "only valid for server mode context" unless @is_server

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
        protocols = "".b
        protos.each do |prot|
          protocol = prot.to_s
          protocols << protocol.length
          protocols << protocol
        end
        protocols
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
          raise "invalid private key or file not found"
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
          raise "invalid certificate or file not found"
        end
      end

      def set_client_ca(ca)
        return unless ca

        if File.file?(ca) && (ca_ptr = SSL.SSL_load_client_CA_file(ca))
          # there is no error checking provided by SSL_CTX_set_client_CA_list
          SSL.SSL_CTX_set_client_CA_list(@ssl_ctx, ca_ptr)
        else
          cleanup
          raise "invalid ca certificate or file not found"
        end
      end
    end

    class Box
      InstanceLookup = ::Concurrent::Map.new

      READ_BUFFER = 2048

      SSL_VERIFY_PEER = 0x01
      SSL_VERIFY_CLIENT_ONCE = 0x04
      def initialize(server, transport, options = {})
        @ready = true

        @handshake_completed = false
        @handshake_signaled = false
        @negotiated = false
        @transport = transport

        @read_buffer = FFI::MemoryPointer.new(:char, READ_BUFFER, false)

        @is_server = server
        @context = Context.new(server, options)
        @bioRead = SSL.BIO_new(SSL.BIO_s_mem)
        @bioWrite = SSL.BIO_new(SSL.BIO_s_mem)
        @ssl = SSL.SSL_new(@context.ssl_ctx)
        SSL.SSL_set_bio(@ssl, @bioRead, @bioWrite)

        @write_queue = []

        InstanceLookup[@ssl.address] = self

        @alpn_fallback = options[:fallback]
        @verify_peer = options[:verify_peer]
        SSL.SSL_set_verify(@ssl, SSL_VERIFY_PEER | SSL_VERIFY_CLIENT_ONCE, VerifyCB) if @verify_peer

        # Add Server Name Indication (SNI) for client connections
        if options[:host_name]
          if server
            @hosts = ::Concurrent::Map.new
            @hosts[options[:host_name].to_s] = @context
            @context.add_server_name_indication
          else
            SSL.SSL_set_tlsext_host_name(@ssl, options[:host_name])
          end
        end

        SSL.SSL_connect(@ssl) unless server
      end

      def add_host(host_name:, **options)
        raise "Server Name Indication (SNI) not configured for default host" unless @hosts
        raise "only valid for server mode context" unless @is_server

        context = Context.new(true, options)
        @hosts[host_name.to_s] = context
        context.add_server_name_indication
        nil
      end

      # Careful with this.
      # If you remove all the hosts you'll end up with a segfault
      def remove_host(host_name)
        raise "Server Name Indication (SNI) not configured for default host" unless @hosts
        raise "only valid for server mode context" unless @is_server

        context = @hosts[host_name.to_s]
        if context
          @hosts.delete(host_name.to_s)
          context.cleanup
        end
        nil
      end

      attr_reader :is_server, :context, :handshake_completed, :hosts, :ssl_version, :cipher, :verify_peer

      def get_peer_cert
        return "" unless @ready

        SSL.SSL_get_peer_certificate(@ssl)
      end

      def negotiated_protocol
        return nil unless @context.alpn_set

        proto = FFI::MemoryPointer.new(:pointer, 1, true)
        len = FFI::MemoryPointer.new(:uint, 1, true)
        SSL.SSL_get0_alpn_selected(@ssl, proto, len)

        resp = proto.get_pointer(0)
        if resp.address == 0
          :failed
        else
          length = len.get_uint(0)
          resp.read_string(length).to_sym
        end
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
          proto = negotiated_protocol

          if proto == :failed
            if @negotiated
              # We should shutdown if this is the case
              @transport.close_cb
              return
            elsif @alpn_fallback
              # Client or Server with a client that doesn't support ALPN
              proto = @alpn_fallback.to_sym
            end
          end
        else
          proto = nil
        end

        @transport.handshake_cb(proto)
      end

      def negotiated
        @negotiated = true
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

      def get_plain_text(buffer, ready)
        # Read the buffered clear text
        size = SSL.SSL_read(@ssl, buffer, ready)
        if size >= 0
          size
        else
          SSL.SSL_get_error(@ssl, size) == SSL_ERROR_WANT_READ ? 0 : -1
        end
      end

      VerifyCB = FFI::Function.new(:int, %i[int pointer]) do |preverify_ok, x509_store|
        x509 = SSL.X509_STORE_CTX_get_current_cert(x509_store)
        ssl = SSL.X509_STORE_CTX_get_ex_data(x509_store, SSL.SSL_get_ex_data_X509_STORE_CTX_idx)

        bio_out = SSL.BIO_new(SSL.BIO_s_mem)
        ret = SSL.PEM_write_bio_X509(bio_out, x509)
        unless ret
          SSL.BIO_free(bio_out)
          raise "Error reading certificate"
        end

        len = SSL.BIO_pending(bio_out)
        buffer = FFI::MemoryPointer.new(:char, len, false)
        size = SSL.BIO_read(bio_out, buffer, len)

        # THis is the callback into the ruby class
        cert = buffer.read_string(size)
        SSL.BIO_free(bio_out)
        InstanceLookup[ssl.address].verify(cert) || preverify_ok.zero? ? 1 : 0
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
            raise CIPHER_DISPATCH_FAILED unless resp > 0

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
end
