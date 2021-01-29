# frozen_string_literal: true

require_relative "support/http_helpers"
require "aws-sdk-s3"

class HTTPXAwsSigv4Test < Minitest::Test
  include ResponseHelpers

  def test_plugin_aws_sigv4_canonical_query
    r1 = sigv4_session.build_request(:get, "http://domain.com?b=c&a=b")
    assert r1.canonical_query == "a=b&b=c"
    r2 = sigv4_session.build_request(:get, "http://domain.com?a=c&a=b")
    assert r2.canonical_query == "a=b&a=c"
    r3 = sigv4_session.build_request(:get, "http://domain.com?a=b&a=b")
    assert r3.canonical_query == "a=b&a=b"
    r4 = sigv4_session.build_request(:get, "http://domain.com?b&a=b")
    assert r4.canonical_query == "a=b&b"
  end

  def test_plugin_aws_sigv4_x_amz_date
    request = sigv4_session.build_request(:get, "http://domain.com")
    # x-amz-date
    assert request.headers.key?("x-amz-date")
    amz_date = Time.parse(request.headers["x-amz-date"])
    assert_in_delta(amz_date, Time.now.utc, 3)

    # date already set
    date = Time.now.utc - 60 * 60 * 24
    date_amz = date.strftime("%Y%m%dT%H%M%SZ")
    x_date_request = sigv4_session.build_request(:get, "http://domain.com", headers: { "x-amz-date" => date_amz })
    verify_header(x_date_request.headers, "x-amz-date", date_amz)
  end

  def test_plugin_aws_sigv4_x_amz_security_token
    request = sigv4_session.build_request(:get, "http://domain.com")
    assert !request.headers.key?("x-amz-security-token")

    tk_request = sigv4_session(security_token: "token").build_request(:get, "http://domain.com")
    assert tk_request.headers.key?("x-amz-security-token")
    verify_header(tk_request.headers, "x-amz-security-token", "token")

    # already set
    token_request = sigv4_session(security_token: "token").build_request(:get, "http://domain.com",
                                                                         headers: { "x-amz-security-token" => "TOKEN" })
    verify_header(token_request.headers, "x-amz-security-token", "TOKEN")
  end

  def test_plugin_aws_sigv4_x_amz_content_sha256
    request = sigv4_session.build_request(:get, "http://domain.com", body: "abcd")
    assert request.headers["x-amz-content-sha256"] == Digest::SHA256.hexdigest("abcd")

    # already set
    hashed_request = sigv4_session.build_request(:get, "http://domain.com", headers: { "x-amz-content-sha256" => "HASH" })
    verify_header(hashed_request.headers, "x-amz-content-sha256", "HASH")
  end

  def test_plugin_aws_sigv4_x_amz_content_sha256_stringio
    request = sigv4_session.build_request(:get, "http://domain.com", body: StringIO.new("abcd"))
    assert request.headers["x-amz-content-sha256"] == Digest::SHA256.hexdigest("abcd")
  end

  def test_plugin_aws_sigv4_x_amz_content_sha256_file
    body = Tempfile.new("httpx")
    body.write("abcd")
    body.flush

    request = sigv4_session.build_request(:get, "http://domain.com", body: body)
    assert request.headers["x-amz-content-sha256"] == Digest::SHA256.hexdigest("abcd")
  ensure
    if body
      body.close
      body.unlink
    end
  end

  def test_plugin_aws_sigv4_authorization_unsigned_headers
    request = sigv4_session(service: "SERVICE", region: "REGION", unsigned_headers: %w[accept user-agent content-type content-length])
              .build_request(:put, "http://domain.com", headers: {
                               "Host" => "domain.com",
                               "Foo" => "foo",
                               "Bar" => "bar  bar",
                               "Bar2" => '"bar  bar"',
                               "Content-Length" => 9,
                               "X-Amz-Date" => "20120101T112233Z",
                             },
                                                        body: StringIO.new("http-body"))
    assert request.headers["authorization"] == "" \
                                               "AWS4-HMAC-SHA256 Credential=akid/20120101/REGION/SERVICE/aws4_request, " \
                                               "SignedHeaders=bar;bar2;foo;host;x-amz-content-sha256;x-amz-date, " \
                                               "Signature=4a7d3e06d1950eb64a3daa1becaa8ba030d9099858516cb2fa4533fab4e8937d"
  end

  AWS_URI = ENV.fetch("AMZ_HOST", "aws:4566")
  USERNAME = ENV.fetch("AWS_ACCESS_KEY_ID", "test")
  PASSWORD = ENV.fetch("AWS_SECRET_ACCESS_KEY", "test")
  def test_plugin_aws_sigv4_get_object
    s3_client = Aws::S3::Client.new(
      endpoint: "http://#{AWS_URI}",
      force_path_style: true
      # http_wire_trace: true,
      # logger: Logger.new(STDERR)
    )
    s3_client.create_bucket(bucket: "test", acl: "private")
    object = s3_client.put_object(bucket: "test", key: "testimage", body: "bucketz")

    # now let's get it
    # no_sig_response = HTTPX.get("http://#{AWS_URI}/test/testimage")
    # verify_error_response(no_sig_response)

    aws_req_headers = object.context.http_request.headers

    response = sigv4_session(username: USERNAME, password: PASSWORD, unsigned_headers: %w[accept content-type content-length])
               .with(headers: {
                       "user-agent" => aws_req_headers["user-agent"],
                       "expect" => "100-continue",
                       "x-amz-date" => aws_req_headers["x-amz-date"],
                       "content-md5" => OpenSSL::Digest.base64digest("MD5", "bucketz"),
                     })
               .put("http://#{AWS_URI}/test/testimage", body: "bucketz")
    verify_status(response, 200)
  end

  private

  def sigv4_session(**options)
    HTTPX.plugin(:aws_sigv4).aws_sigv4_authentication(service: "s3", region: "us-east-1", username: "akid", password: "secret", **options)
  end
end
