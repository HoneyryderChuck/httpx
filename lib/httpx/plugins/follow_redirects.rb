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
      REQUEST_BODY_HEADERS = %w[transfer-encoding content-encoding content-type content-length content-language content-md5 trailer].freeze

      using URIExtensions

      module OptionsMethods
        def option_max_redirects(value)
          num = Integer(value)
          raise TypeError, ":max_redirects must be positive" if num.negative?

          num
        end

        def option_follow_insecure_redirects(value)
          value
        end

        def option_allow_auth_to_other_origins(value)
          value
        end

        def option_redirect_on(value)
          raise TypeError, ":redirect_on must be callable" unless value.respond_to?(:call)

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

          redirect_uri = __get_location_from_response(response)

          if options.redirect_on
            redirect_allowed = options.redirect_on.call(redirect_uri)
            return response unless redirect_allowed
          end

          # build redirect request
          request_body = redirect_request.body
          redirect_method = "GET"
          redirect_params = {}

          if response.status == 305 && options.respond_to?(:proxy)
            request_body.rewind
            # The requested resource MUST be accessed through the proxy given by
            # the Location field. The Location field gives the URI of the proxy.
            redirect_options = options.merge(headers: redirect_request.headers,
                                             proxy: { uri: redirect_uri },
                                             max_redirects: max_redirects - 1)

            redirect_params[:body] = request_body
            redirect_uri = redirect_request.uri
            options = redirect_options
          else
            redirect_headers = redirect_request_headers(redirect_request.uri, redirect_uri, request.headers, options)
            redirect_opts = Hash[options]
            redirect_params[:max_redirects] = max_redirects - 1

            unless request_body.empty?
              if response.status == 307
                # The method and the body of the original request are reused to perform the redirected request.
                redirect_method = redirect_request.verb
                request_body.rewind
                redirect_params[:body] = request_body
              else
                # redirects are **ALWAYS** GET, so remove body-related headers
                REQUEST_BODY_HEADERS.each do |h|
                  redirect_headers.delete(h)
                end
                redirect_params[:body] = nil
              end
            end

            options = options.class.new(redirect_opts.merge(headers: redirect_headers.to_h))
          end

          redirect_uri = Utils.to_uri(redirect_uri)

          if !options.follow_insecure_redirects &&
             response.uri.scheme == "https" &&
             redirect_uri.scheme == "http"
            error = InsecureRedirectError.new(redirect_uri.to_s)
            error.set_backtrace(caller)
            return ErrorResponse.new(request, error)
          end

          retry_request = build_request(redirect_method, redirect_uri, redirect_params, options)

          request.redirect_request = retry_request

          redirect_after = response.headers["retry-after"]

          if redirect_after
            # Servers send the "Retry-After" header field to indicate how long the
            # user agent ought to wait before making a follow-up request.
            # When sent with any 3xx (Redirection) response, Retry-After indicates
            # the minimum time that the user agent is asked to wait before issuing
            # the redirected request.
            #
            redirect_after = Utils.parse_retry_after(redirect_after)

            log { "redirecting after #{redirect_after} secs..." }

            deactivate_connection(request, connections, options)

            pool.after(redirect_after) do
              if request.response
                # request has terminated abruptly meanwhile
                retry_request.emit(:response, request.response)
              else
                send_request(retry_request, connections, options)
              end
            end
          else
            send_request(retry_request, connections, options)
          end
          nil
        end

        def redirect_request_headers(original_uri, redirect_uri, headers, options)
          headers = headers.dup

          return headers if options.allow_auth_to_other_origins

          return headers unless headers.key?("authorization")

          return headers if original_uri.origin == redirect_uri.origin

          headers.delete("authorization")

          headers
        end

        def __get_location_from_response(response)
          # @type var location_uri: http_uri
          location_uri = URI(response.headers["location"])
          location_uri = response.uri.merge(location_uri) if location_uri.relative?
          location_uri
        end
      end

      module RequestMethods
        attr_accessor :root_request

        def redirect_request
          @redirect_request || self
        end

        def redirect_request=(req)
          @redirect_request = req
          req.root_request = @root_request || self
          @response = nil
        end

        def response
          return super unless @redirect_request && @response.nil?

          @redirect_request.response
        end

        def max_redirects
          @options.max_redirects || MAX_REDIRECTS
        end
      end

      module ConnectionMethods
        private

        def set_request_request_timeout(request)
          return unless request.root_request.nil?

          super
        end
      end
    end
    register_plugin :follow_redirects, FollowRedirects
  end
end
