# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin applies AWS Sigv4 to requests, using the AWS SDK credentials and configuration.
    #
    # It requires the "aws-sdk-core" gem.
    #
    module AwsSdkAuthentication
      #
      # encapsulates access to an AWS SDK credentials store.
      #
      class Credentials
        def initialize(aws_credentials)
          @aws_credentials = aws_credentials
        end

        def username
          @aws_credentials.access_key_id
        end

        def password
          @aws_credentials.secret_access_key
        end

        def security_token
          @aws_credentials.session_token
        end
      end

      class << self
        attr_reader :credentials, :region

        def load_dependencies(_klass)
          require "aws-sdk-core"

          client = Class.new(Seahorse::Client::Base) do
            @identifier = :httpx
            set_api(Aws::S3::ClientApi::API)
            add_plugin(Aws::Plugins::CredentialsConfiguration)
            add_plugin(Aws::Plugins::RegionalEndpoint)
            class << self
              attr_reader :identifier
            end
          end.new

          @credentials = Credentials.new(client.config[:credentials])
          @region = client.config[:region]
        end

        def configure(klass)
          klass.plugin(:aws_sigv4)
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end
      end

      module InstanceMethods
        #
        # aws_authentication
        # aws_authentication(credentials: Aws::Credentials.new('akid', 'secret'))
        # aws_authentication()
        #
        def aws_sdk_authentication(**options)
          credentials = AwsSdkAuthentication.credentials
          region = AwsSdkAuthentication.region

          aws_sigv4_authentication(
            credentials: credentials,
            region: region,
            provider_prefix: "aws",
            header_provider_field: "amz",
            **options
          )
        end
        alias_method :aws_auth, :aws_sdk_authentication
      end
    end
    register_plugin :aws_sdk_authentication, AwsSdkAuthentication
  end
end
