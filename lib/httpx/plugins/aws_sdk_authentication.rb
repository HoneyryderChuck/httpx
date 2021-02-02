# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to apply AWS Sigv4 to AWS cloud requests.
    #
    module AwsSdkAuthentication
      class << self
        attr_reader :credentials, :region

        def load_dependencies(klass)
          require "aws-sdk-core"
          klass.plugin(:aws_sigv4)

          client = Class.new(Seahorse::Client::Base) do
            @identifier = :httpx
            set_api(Aws::S3::ClientApi::API) 
            add_plugin(Aws::Plugins::CredentialsConfiguration)
            add_plugin(Aws::Plugins::RegionalEndpoint)
            class << self
              attr_reader :identifier
            end
          end.new 
          

          @credentials = client.config[:credentials]
          @region = client.config[:region]  
        end
      end

      module InstanceMethods
        #
        # aws_authentication
        # aws_authentication(credentials: Aws::Credentials.new('akid', 'secret'))
        # aws_authentication()
        #
        def aws_sdk_authentication(options = nil)
          credentials = AwsSdkAuthentication.credentials
          region = AwsSdkAuthentication.region

          aws_sigv4_authentication(
            username: credentials.access_key_id,
            password: credentials.secret_access_key,
            security_token: credentials.session_token,
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
