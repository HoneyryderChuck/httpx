# frozen_string_literal: true

module Requests
  module Plugins
    module PushPromise
      def test_plugin_no_push_promise
        html, css = HTTPX.get(push_html_uri, push_css_uri, max_concurrent_requests: 1, http2_settings: { settings_enable_push: 1 })
        verify_status(html, 200)
        verify_status(css, 200)
        verify_no_header(css.headers, "x-http2-push")
        html.close
        css.close
      end

      def test_plugin_push_promise_get
        session = HTTPX.plugin(:push_promise)
        html, css = session.get(push_html_uri, push_css_uri)
        verify_status(html, 200)
        verify_status(css, 200)
        verify_header(css.headers, "x-http2-push", "1")
        assert css.pushed?
        html.close
        css.close
      end

      def test_plugin_push_promise_concurrent
        session = HTTPX.plugin(:push_promise)
                       .with(max_concurrent_requests: 100)
        html, css = session.get(push_html_uri, push_css_uri)
        verify_status(html, 200)
        verify_status(css, 200)
        verify_no_header(css.headers, "x-http2-push")
        assert !css.pushed?
        html.close
        css.close
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
