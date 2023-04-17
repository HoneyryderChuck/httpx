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
    # https://gitlab.com/os85/httpx/wikis/Follow-Redirects
    #
    module FollowRedirects
      MAX_REDIRECTS = 3
      REDIRECT_STATUS = (300..399).freeze

      module OptionsMethods
        def option_max_redirects(value)
          num = Integer(value)
          raise TypeError, ":max_redirects must be positive" if num.negative?

          num
        end

        def option_follow_insecure_redirects(value)
          value
        end
      end

      module InstanceMethods
        def max_redirects(n)
          with(max_redirects: n.to_i)
        end

        private

        def fetch_response(request, connections, options)
          redirect_request = request.redirect_request
          response = super(redirect_request, connections, options)
          return unless response

          max_redirects = redirect_request.max_redirects

          return response unless response.is_a?(Response)
          return response unless REDIRECT_STATUS.include?(response.status) && response.headers.key?("location")
          return response unless max_redirects.positive?

          retry_request = build_redirect_request(redirect_request, response, options)

          request.redirect_request = retry_request

          if !options.follow_insecure_redirects &&
             response.uri.scheme == "https" &&
             retry_request.uri.scheme == "http"
            error = InsecureRedirectError.new(retry_request.uri.to_s)
            error.set_backtrace(caller)
            return ErrorResponse.new(request, error, options)
          end

          retry_after = response.headers["retry-after"]

          if retry_after
            # Servers send the "Retry-After" header field to indicate how long the
            # user agent ought to wait before making a follow-up request.
            # When sent with any 3xx (Redirection) response, Retry-After indicates
            # the minimum time that the user agent is asked to wait before issuing
            # the redirected request.
            #
            retry_after = Utils.parse_retry_after(retry_after)

            log { "redirecting after #{retry_after} secs..." }
            pool.after(retry_after) do
              connection = find_connection(retry_request, connections, options)
              connection.send(retry_request)
            end
          else
            connection = find_connection(retry_request, connections, options)
            connection.send(retry_request)
          end
          nil
        end

        def build_redirect_request(request, response, options)
          redirect_uri = __get_location_from_response(response)
          max_redirects = request.max_redirects

          if response.status == 305 && options.respond_to?(:proxy)
            # The requested resource MUST be accessed through the proxy given by
            # the Location field. The Location field gives the URI of the proxy.
            retry_options = options.merge(headers: request.headers,
                                          proxy: { uri: redirect_uri },
                                          body: request.body,
                                          max_redirects: max_redirects - 1)
            redirect_uri = request.url
          else

            # redirects are **ALWAYS** GET
            retry_options = options.merge(headers: request.headers,
                                          body: request.body,
                                          max_redirects: max_redirects - 1)
          end

          build_request("GET", redirect_uri, retry_options)
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

        def response
          return super unless @redirect_request

          @redirect_request.response
        end

        def max_redirects
          @options.max_redirects || MAX_REDIRECTS
        end
      end
    end
    register_plugin :follow_redirects, FollowRedirects
  end
end
