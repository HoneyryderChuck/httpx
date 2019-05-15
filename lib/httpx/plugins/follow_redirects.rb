# frozen_string_literal: true

module HTTPX
  InsecureRedirectError = Class.new(Error)
  module Plugins
    #
    # This plugin adds support for following redirect (status 30X) responses.
    #
    # It has an upper bound of followed redirects (see *MAX_REDIRECTS*), after which it
    # will return the last redirect response. It will **not** raise an exception.
    #
    # It also doesn't follow insecure redirects (https -> http) by default (see *follow_insecure_redirects*).
    #
    module FollowRedirects
      MAX_REDIRECTS = 3
      REDIRECT_STATUS = (300..399).freeze

      def self.extra_options(options)
        Class.new(options.class) do
          def_option(:max_redirects) do |num|
            num = Integer(num)
            raise Error, ":max_redirects must be positive" unless num.positive?

            num
          end

          def_option(:follow_insecure_redirects)
        end.new(options)
      end

      module InstanceMethods
        def max_redirects(n)
          branch(default_options.with_max_redirects(n.to_i))
        end

        private

        def fetch_response(request, connections, options)
          redirect_request = request.redirect_request
          response = super(redirect_request, connections, options)
          return unless response

          max_redirects = redirect_request.max_redirects

          return response unless REDIRECT_STATUS.include?(response.status)
          return response unless max_redirects.positive?

          retry_request = build_redirect_request(redirect_request, response, options)

          request.redirect_request = retry_request

          if !options.follow_insecure_redirects &&
             response.uri.scheme == "https" &&
             retry_request.uri.scheme == "http"
            error = InsecureRedirectError.new(retry_request.uri.to_s)
            error.set_backtrace(caller)
            return ErrorResponse.new(error, options)
          end

          connection = find_connection(retry_request, connections, options)
          connection.send(retry_request)
          nil
        end

        def build_redirect_request(request, response, options)
          redirect_uri = __get_location_from_response(response)
          max_redirects = request.max_redirects

          # redirects are **ALWAYS** GET
          retry_options = options.merge(headers: request.headers,
                                        body: request.body,
                                        max_redirects: max_redirects - 1)
          build_request(:get, redirect_uri, retry_options)
        end

        def __get_location_from_response(response)
          location_uri = URI(response.headers["location"])
          location_uri = response.uri.merge(location_uri) if location_uri.relative?
          location_uri
        end
      end

      module RequestMethods
        def self.included(klass)
          klass.__send__(:attr_writer, :redirect_request)
        end

        def redirect_request
          @redirect_request || self
        end

        def max_redirects
          @options.max_redirects || MAX_REDIRECTS
        end
      end
    end
    register_plugin :follow_redirects, FollowRedirects
  end
end
