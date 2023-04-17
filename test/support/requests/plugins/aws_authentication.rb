# frozen_string_literal: true

require "aws-sdk-s3"

module Requests
  module Plugins
    module AWSAuthentication
      AWS_URI = ENV.fetch("AMZ_HOST", "aws:4566")

      def test_plugin_aws_authentication_put_object
        amz_uri = origin(AWS_URI)

        begin
          s3_client = Aws::S3::Client.new(
            endpoint: amz_uri,
            force_path_style: true,
            ssl_verify_peer: false,
            # http_wire_trace: true,
            # logger: Logger.new(STDERR)
          )
          s3_client.create_bucket(bucket: "test", acl: "private")
          object = s3_client.put_object(bucket: "test", key: "testimage", body: "bucketz")
        rescue Aws::S3::Errors::BucketAlreadyExists
          # because this test will run 2 times (http and https)
        end

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

        # testing here to make sure the plugin is loaded
        config = HTTPX::Plugins::AwsSdkAuthentication::Configuration.new("default")
        assert config.respond_to?(:balls)
        assert config.balls.nil?
      end

      private

      def aws_s3_session(**options)
        HTTPX.plugin(:aws_sdk_authentication, aws_profile: "default").aws_sdk_authentication(service: "s3", **options)
      end
    end
  end
end
