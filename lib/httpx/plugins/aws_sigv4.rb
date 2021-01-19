# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds AWS Sigv4 authentication.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/AWS-SigV4
    #
    module AWSSigV4
      class Signer
        def initialize(options = {})
          @unsigned_headers = options.fetch(:unsigned_headers, [])
        end

        def sign!(request); end
      end

      class << self
        def extra_options(options)
          Class.new(options.class) do
            def_option(:sigv4_signer) do |signer|
              if signer.is_a?(Signer)
                signer
              else
                Jar.new(signer)
              end
            end
          end.new(options)
        end

        def load_dependencies(klass)
          klass.plugin(:authentication)
        end
      end

      module InstanceMethods
        def build_request(*, _)
          request = super

          return request unless @options.sigv4_signer && !request.headers.key?("authorization")

          @options.sigv4_signer.sign!(request)

          request
        end
      end
    end
    register_plugin :aws_sigv4, AWSSigV4
  end
end
