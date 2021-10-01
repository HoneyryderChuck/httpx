# frozen_string_literal: true

module Requests
  module Plugins
    module PushPromise
      def test_plugin_no_push_promise
        html, css = no_push_promise_client.get(push_html_uri, push_css_uri, max_concurrent_requests: 1,
                                                                            http2_settings: { settings_enable_push: 1 })
        verify_status(html, 200)
        verify_status(css, 200)
        verify_no_header(css.headers, "x-http2-push")
        html.close
        css.close
      end

      def test_plugin_push_promise_get
        session = push_promise_client
        html, css = session.get(push_html_uri, push_css_uri)
        verify_status(html, 200)
        verify_status(css, 200)
        verify_header(css.headers, "x-http2-push", "1")
        assert css.pushed?
        html.close
        css.close
      end

      def test_plugin_push_promise_concurrent
        session = push_promise_client.with(max_concurrent_requests: 100)
        html, css = session.get(push_html_uri, push_css_uri)
        verify_status(html, 200)
        verify_status(css, 200)
        verify_no_header(css.headers, "x-http2-push")
        assert !css.pushed?
        html.close
        css.close
      end

      private

      if RUBY_VERSION.start_with?("2.3")
        def no_push_promise_client
          HTTPX.with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
        end

        def push_promise_client
          no_push_promise_client.plugin(:push_promise)
        end
      else
        def no_push_promise_client
          HTTPX
        end

        def push_promise_client
          HTTPX.plugin(:push_promise)
        end
      end

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
