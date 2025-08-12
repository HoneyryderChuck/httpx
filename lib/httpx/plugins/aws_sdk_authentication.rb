# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin applies AWS Sigv4 to requests, using the AWS SDK credentials and configuration.
    #
    # It requires the "aws-sdk-core" gem.
    #
    module AwsSdkAuthentication
      # Mock configuration, to be used only when resolving credentials
      class Configuration
        attr_reader :profile

        def initialize(profile)
          @profile = profile
        end

        def respond_to_missing?(*)
          true
        end

        def method_missing(*); end
      end

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
        def load_dependencies(_klass)
          require "aws-sdk-core"
        end

        def configure(klass)
          klass.plugin(:aws_sigv4)
        end

        def extra_options(options)
          options.merge(max_concurrent_requests: 1)
        end

        def credentials(profile)
          mock_configuration = Configuration.new(profile)
          Credentials.new(Aws::CredentialProviderChain.new(mock_configuration).resolve)
        end

        def region(profile)
          # https://github.com/aws/aws-sdk-ruby/blob/version-3/gems/aws-sdk-core/lib/aws-sdk-core/plugins/regional_endpoint.rb#L62
          keys = %w[AWS_REGION AMAZON_REGION AWS_DEFAULT_REGION]
          env_region = ENV.values_at(*keys).compact.first
          env_region = nil if env_region == ""
          cfg_region = Aws.shared_config.region(profile: profile)
          env_region || cfg_region
        end
      end

      # adds support for the following options:
      #
      # :aws_profile :: AWS account profile to retrieve credentials from.
      module OptionsMethods
        private

        def option_aws_profile(value)
          String(value)
        end
      end

      module InstanceMethods
        #
        # aws_authentication
        # aws_authentication(credentials: Aws::Credentials.new('akid', 'secret'))
        # aws_authentication()
        #
        def aws_sdk_authentication(
          credentials: AwsSdkAuthentication.credentials(@options.aws_profile),
          region: AwsSdkAuthentication.region(@options.aws_profile),
          **options
        )

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
