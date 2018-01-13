# frozen_string_literal: true

module Requests
  module Plugins
    module PushPromise
      def test_plugin_push_promise_get
        client = HTTPX.plugin(:push_promise)
        html, css = client.get(push_html_uri, push_css_uri)
        verify_status(html.status, 200)
        verify_status(css.status, 200)
        verify_header(css.headers, "x-http2-push", "1")
      end

      def test_plugin_push_promise_concurrent
        client = HTTPX.plugin(:push_promise)
                      .with(max_concurrent_requests: 100)
        html, css = client.get(push_html_uri, push_css_uri)
        verify_status(html.status, 200)
        verify_status(css.status, 200)
        verify_no_header(css.headers, "x-http2-push")
      end

      private

      def push_origin
        "https://nghttp2.org"
      end

      def push_html_uri
        "#{push_origin}/"
      end
      
      def push_css_uri
        "#{push_origin}/stylesheets/screen.css" 
      end
    end
  end
end

