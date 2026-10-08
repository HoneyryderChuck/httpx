# frozen_string_literal: true

module Requests
  module Plugins
    module PushPromise
      def test_plugin_push_promise_get
        start_test_servlet(PushPromiseServer, num_promises: 2) do |server|
          uri = "#{server.origin}/"
          session = HTTPX.plugin(:push_promise).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
          parent, child1, child2 = session.get(uri, "#{uri}0", "#{uri}1")
          verify_status(parent, 200)
          verify_status(child1, 200)
          verify_status(child2, 200)
          verify_header(child1.headers, "x-http2-push", "1")
          verify_header(child2.headers, "x-http2-push", "1")
          assert child1.pushed?
          assert child2.pushed?
        end
      end

      def test_plugin_push_promise_settings_enable_push_0
        start_test_servlet(PushPromiseServer) do |server|
          uri = "#{server.origin}/"
          session = HTTPX.plugin(:push_promise).with(http2_settings: { settings_enable_push: 0 },
                                                     ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
          parent, child = session.get(uri, "#{uri}0")
          verify_status(parent, 200)
          verify_status(child, 200)
          verify_no_header(child.headers, "x-http2-push")
          assert !child.pushed?
        end
      end

      def test_plugin_push_promise_concurrent
        start_test_servlet(PushPromiseServer) do |server|
          uri = "#{server.origin}/"
          session = HTTPX.plugin(:push_promise).with(max_concurrent_requests: 100, ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
          parent, child = session.get(uri, "#{uri}0")
          verify_status(parent, 200)
          verify_status(child, 200)
          verify_no_header(child.headers, "x-http2-push")
          assert !child.pushed?
        end
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
