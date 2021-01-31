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

module HTTPX::TLS::SSL
  Error = HTTPX::TLS::Error

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
  attach_function :SSL_CTX_set_verify, %i[ssl int verify_callback], :void
  attach_function :SSL_get_verify_result, %i[ssl], :long
  attach_function :SSL_connect, [:ssl], :int

  # Verify callback
  X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT = 2
  X509_V_ERR_HOSTNAME_MISMATCH = 62
  X509_V_ERR_CERT_REJECTED = 28
  attach_function :X509_STORE_CTX_get_current_cert, [:pointer], :x509
  attach_function :SSL_get_ex_data_X509_STORE_CTX_idx, [], :int
  attach_function :X509_STORE_CTX_get_ex_data, %i[pointer int], :ssl
  attach_function :X509_STORE_CTX_get_error_depth, %i[x509], :int
  attach_function :PEM_write_bio_X509, %i[bio x509], :bool
  attach_function :X509_verify_cert_error_string, %i[long], :string
  attach_function :X509_STORE_CTX_set_error, %i[ssl_ctx long], :void

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
    raise Error, "error setting SNI hostname" if SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, name_ptr).zero?
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

  PrivateMaterials = <<~KEYSTR
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
  KEYSTR

  BuiltinPasswdCB = FFI::Function.new(:int, %i[pointer int int pointer]) do |buffer, _len, _flag, _data|
    buffer.write_string("kittycat")
    8
  end

  #  Save RAM by releasing read and write buffers when they're empty
  SSL_MODE_RELEASE_BUFFERS = 0x00000010
  SSL_OP_ALL = 0x80000BFF
  SSL_FILETYPE_PEM = 1

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
end
