# frozen_string_literal: true

require "aws-sdk-s3"

module Requests
  module Plugins
    module AWSAuthentication
      AWS_URI = ENV.fetch("AMZ_HOST", "aws:4566")

      def test_plugin_aws_authentication_put_object
        amz_uri = origin(AWS_URI)

        s3_client = Aws::S3::Client.new(
          endpoint: amz_uri,
          force_path_style: true,
          ssl_verify_peer: false,
          # http_wire_trace: true,
          # logger: Logger.new(STDERR)
        )
        s3_client.create_bucket(bucket: "test", acl: "private")
        object = s3_client.put_object(bucket: "test", key: "testimage", body: "bucketz")

        # now let's get it
        # no_sig_response = HTTPX.get("http://#{AWS_URI}/test/testimage")
        # verify_error_response(no_sig_response)

        aws_req_headers = object.context.http_request.headers

        response = aws_s3_session(unsigned_headers: %w[accept content-type content-length])
                   .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
                         headers: {
                           "user-agent" => aws_req_headers["user-agent"],
                           # gotta fix localstack first
                           # "expect" => "100-continue",
                           "x-amz-date" => aws_req_headers["x-amz-date"],
                           "content-md5" => OpenSSL::Digest.base64digest("MD5", "bucketz"),
                         })
                   .put("#{amz_uri}/test/testimage", body: "bucketz")
        verify_status(response, 200)
      end

      private

      def aws_s3_session(**options)
        HTTPX.plugin(:aws_sdk_authentication).aws_sdk_authentication(service: "s3", **options)
      end
    end
  end
end