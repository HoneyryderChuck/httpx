# frozen_string_literal: true

require "cgi"

module Requests
  module Plugins
    module FollowRedirects
      def test_plugin_follow_redirects
        no_redirect_response = HTTPX.get(redirect_uri)
        verify_status(no_redirect_response.status, 302)
        verify_header(no_redirect_response.headers, "location", redirect_location) 
        
        client = HTTPX.plugin(:follow_redirects)
        redirect_response = client.get(redirect_uri)
        verify_status(redirect_response.status, 200)
        require "pry-byebug" ; binding.pry
      end

      def test_plugin_follow_redirects_max_redirects

      end

      private

      def redirect_uri
        build_uri("/redirect-to?url=" + CGI.escape(redirect_location))
      end

      def redirect_location
        build_uri("/")
      end
    end
  end
end

