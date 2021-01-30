# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to apply AWS Sigv4 to AWS cloud requests.
    #
    module AWSAuthentication
      class << self
        def load_dependencies(klass)
          require "aws-sdk-core"
          klass.plugin(:aws_sigv4)
        end
      end

      module InstanceMethods
        #
        # aws_authentication
        # aws_authentication(credentials: Aws::Credentials.new('akid', 'secret'))
        # aws_authentication()
        #
        def aws_authentication(options = nil)
          s3_client = Aws::S3::Client.new
          credentials = s3_client.config[:credentials]

          aws_sigv4_authentication(
            username: credentials.access_key_id,
            password: credentials.secret_access_key,
            security_token: credentials.session_token,
            region: s3_client.config[:region],
            provider_prefix: "aws",
            header_provider_field: "amz",
            **options
          )
        end
        alias_method :aws_auth, :aws_authentication
      end
    end
    register_plugin :aws_authentication, AWSAuthentication
  end
end
