# frozen_string_literal: true

module HTTPX
  module Plugins
    module FollowRedirects
      module InstanceMethods

        MAX_REDIRECTS = 3
        REDIRECT_STATUS = 300..399

        def max_redirects(n)
          branch(default_options.with_max_redirects(n.to_i))
        end

        def request(*args, **options)
          begin
            # do not needlessly close channels
            keep_open = @keep_open
            @keep_open = true
            
            max_redirects = @default_options.max_redirects || MAX_REDIRECTS
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
        end

        private

        def __build_redirect_req(request, response, options)
          redirect_uri = URI(response.headers["location"])
          redirect_uri = response.uri.merge(redirect_uri) if redirect_uri.relative?

          # TODO: integrate cookies in the next request
          # redirects are **ALWAYS** GET
          retry_options = options.merge(headers: request.headers,
                                        body: request.body)
          __build_req(:get, redirect_uri, retry_options)
        end
      end

      module OptionsMethods
        def self.included(klass)
          super
          klass.def_option(:max_redirects)
        end
      end        
    end
    register_plugin :follow_redirects, FollowRedirects
  end
end

