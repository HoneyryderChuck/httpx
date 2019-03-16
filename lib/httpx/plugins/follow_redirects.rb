# frozen_string_literal: true

module HTTPX
  InsecureRedirectError = Class.new(Error)
  module Plugins
    module FollowRedirects
      module InstanceMethods
        MAX_REDIRECTS = 3
        REDIRECT_STATUS = (300..399).freeze

        def max_redirects(n)
          branch(default_options.with_max_redirects(n.to_i))
        end

        def request(*args, **options)
          # do not needlessly close connections
          keep_open = @keep_open
          @keep_open = true

          max_redirects = @options.max_redirects || MAX_REDIRECTS
          requests = __build_reqs(*args, **options)
          responses = __send_reqs(*requests)

          loop do
            redirect_requests = []
            indexes = responses.each_with_index.map do |response, index|
              next unless REDIRECT_STATUS.include?(response.status)

              request = requests[index]
              retry_request = __build_redirect_req(request, response, options)
              redirect_requests << retry_request
              index
            end.compact
            break if redirect_requests.empty?
            break if max_redirects <= 0

            max_redirects -= 1

            redirect_responses = __send_reqs(*redirect_requests)
            indexes.each_with_index do |index, i2|
              requests[index] = redirect_requests[i2]
              responses[index] = redirect_responses[i2]
            end
          end

          return responses.first if responses.size == 1

          responses
        ensure
          @keep_open = keep_open
        end

        private

        def fetch_response(request)
          response = super
          if response &&
             REDIRECT_STATUS.include?(response.status) &&
             !@options.follow_insecure_redirects
            redirect_uri = __get_location_from_response(response)
            if response.uri.scheme == "https" &&
               redirect_uri.scheme == "http"
              error = InsecureRedirectError.new(redirect_uri.to_s)
              error.set_backtrace(caller)
              response = ErrorResponse.new(error, @options)
            end
          end
          response
        end

        def __build_redirect_req(request, response, options)
          redirect_uri = __get_location_from_response(response)

          # TODO: integrate cookies in the next request
          # redirects are **ALWAYS** GET
          retry_options = options.merge(headers: request.headers,
                                        body: request.body)
          __build_req(:get, redirect_uri, retry_options)
        end

        def __get_location_from_response(response)
          location_uri = URI(response.headers["location"])
          location_uri = response.uri.merge(location_uri) if location_uri.relative?
          location_uri
        end
      end

      module OptionsMethods
        def self.included(klass)
          super
          klass.def_option(:max_redirects) do |num|
            num = Integer(num)
            raise Error, ":max_redirects must be positive" unless num.positive?

            num
          end

          klass.def_option(:follow_insecure_redirects)
        end
      end
    end
    register_plugin :follow_redirects, FollowRedirects
  end
end
