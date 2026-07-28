# frozen_string_literal: true

require_relative "test_helper"

class ConnectionTest < Minitest::Test
  include HTTPX
  include HTTPHelpers

  DUMMY_SESSION = <<~__EOS__
    -----BEGIN SSL SESSION PARAMETERS-----
    MIIDzQIBAQICAwMEAsAUBCAF219w9ZEV8dNA60cpEGOI34hJtIFbf3bkfzSgMyad
    MQQwyGLbkCxE4OiMLdKKem+pyh8V7ifoP7tCxhdmwoDlJxI1v6nVCjai+FGYuncy
    NNSWoQYCBE4DDWuiAwIBCqOCAo4wggKKMIIBcqADAgECAgECMA0GCSqGSIb3DQEB
    BQUAMD0xEzARBgoJkiaJk/IsZAEZFgNvcmcxGTAXBgoJkiaJk/IsZAEZFglydWJ5
    LWxhbmcxCzAJBgNVBAMMAkNBMB4XDTExMDYyMzA5NTQ1MVoXDTExMDYyMzEwMjQ1
    MVowRDETMBEGCgmSJomT8ixkARkWA29yZzEZMBcGCgmSJomT8ixkARkWCXJ1Ynkt
    bGFuZzESMBAGA1UEAwwJbG9jYWxob3N0MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCB
    iQKBgQDLwsSw1ECnPtT+PkOgHhcGA71nwC2/nL85VBGnRqDxOqjVh7CxaKPERYHs
    k4BPCkE3brtThPWc9kjHEQQ7uf9Y1rbCz0layNqHyywQEVLFmp1cpIt/Q3geLv8Z
    D9pihowKJDyMDiN6ArYUmZczvW4976MU3+l54E6lF/JfFEU5hwIDAQABoxIwEDAO
    BgNVHQ8BAf8EBAMCBaAwDQYJKoZIhvcNAQEFBQADggEBACj5WhoZ/ODVeHpwgq1d
    8fW/13ICRYHYpv6dzlWihyqclGxbKMlMnaVCPz+4JaVtMz3QB748KJQgL3Llg3R1
    ek+f+n1MBCMfFFsQXJ2gtLB84zD6UCz8aaCWN5/czJCd7xMz7fRLy3TOIW5boXAU
    zIa8EODk+477K1uznHm286ab0Clv+9d304hwmBZgkzLg6+31Of6d6s0E0rwLGiS2
    sOWYg34Y3r4j8BS9Ak4jzpoLY6cJ0QAKCOJCgmjGr4XHpyXMLbicp3ga1uSbwtVO
    gF/gTfpLhJC+y0EQ5x3Ftl88Cq7ZJuLBDMo/TLIfReJMQu/HlrTT7+LwtneSWGmr
    KkSkAgQApQMCAROqgcMEgcAuDkAVfj6QAJMz9yqTzW5wPFyty7CxUEcwKjUqj5UP
    /Yvky1EkRuM/eQfN7ucY+MUvMqv+R8ZSkHPsnjkBN5ChvZXjrUSZKFVjR4eFVz2V
    jismLEJvIFhQh6pqTroRrOjMfTaM5Lwoytr2FTGobN9rnjIRsXeFQW1HLFbXn7Dh
    8uaQkMwIVVSGRB8T7t6z6WIdWruOjCZ6G5ASI5XoqAHwGezhLodZuvJEfsVyCF9y
    j+RBGfCFrrQbBdnkFI/ztgM=
    -----END SSL SESSION PARAMETERS-----
  __EOS__

  def test_merge_ssl_session_before_tls_negotiated
    connection = build_ssl_connection(origin)
    coalesced_connection = build_ssl_connection(coalesced_origin)

    coalesced_connection.instance_variable_set(:@ssl_session, session = dummy_ssl_session)

    connection.merge(coalesced_connection)

    assert connection.origins == [origin, coalesced_origin]
    assert connection.instance_variable_get(:@ssl_session) == session
    assert connection.io.instance_variable_get(:@ssl_session) == session

    tls_session_established(connection, new_session = dummy_ssl_session)

    assert connection.instance_variable_get(:@ssl_session) == new_session
    assert connection.io.instance_variable_get(:@ssl_session) == new_session
  end

  def test_merge_ssl_session_after_tls_negotiated
    connection = build_ssl_connection(origin)
    negotiate_tls(connection)
    coalesced_connection = build_ssl_connection(coalesced_origin)
    coalesced_connection.instance_variable_set(:@ssl_session, session = dummy_ssl_session)

    connection.merge(coalesced_connection)

    assert connection.origins == [origin, coalesced_origin]
    assert connection.instance_variable_get(:@ssl_session) == session

    tls_session_established(connection, new_session = dummy_ssl_session)

    assert connection.instance_variable_get(:@ssl_session) == new_session
    assert connection.io.instance_variable_get(:@ssl_session) == new_session
  end

  private

  def build_ssl_connection(uri)
    uri = URI(uri)
    connection = Connection.new(uri, Options.new)
    ipaddrs = Resolv.getaddresses(uri.host)
    connection.addresses = ipaddrs.map(&Resolver::Entry.method(:new))
    connection
  end

  def negotiate_tls(connection)
    io = connection.io
    until io.state == :negotiated
      io.connect

      case io.interests
      when :r
        io.to_io.wait_readable(1)
      when :w
        io.to_io.wait_writable(1)
      when :rw
        IO.select([io], [io], nil, 1)
      end
    end
  end

  def tls_session_established(connection, session)
    connection.io.instance_variable_get(:@ctx).session_new_cb.call(nil, session)
  end

  def dummy_ssl_session
    OpenSSL::SSL::Session.new(DUMMY_SESSION)
  end

  def coalesced_origin
    "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"
  end

  def scheme
    "https://"
  end
end unless RUBY_ENGINE == "jruby"
# TODO: remove this once jruby-openssl supports OpenSSL::SSL::Sesssion.new(String)
