# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for using the experimental QUERY HTTP method
    #
    # https://gitlab.com/os85/httpx/wikis/Query
    module Query
      def self.subplugins
        {
          retries: QueryRetries,
        }
      end

      module InstanceMethods
        def query(*uri, **options)
          request("QUERY", uri, **options)
        end
      end

      module QueryRetries
        module InstanceMethods
          private

          def retryable_request?(request, *)
            super || request.verb == "QUERY"
          end
        end
      end
    end

    register_plugin :query, Query
  end
end
