# frozen_string_literal: true

module Requests
  module Plugins
    module ServerSentEvents
      def test_plugin_server_sent_events
        session = HTTPX.plugin(:server_sent_events).with(ssl: { verify_hostname: false })

        start_test_servlet(SSE, tls: tls?, messages: [{ data: "test" }]) do |server|
          uri = "#{server.origin}/"

          no_sse_response = session.get(uri)
          sse_response = session.get(uri, event_stream: true)

          assert sse_response.respond_to?(:headers) # test respond_to_missing?

          no_sse_headers = no_sse_response.headers
          no_sse_headers.delete("date")
          sse_headers = sse_response.headers
          sse_headers.delete("date")

          verify_header(no_sse_headers, "content-type", "text/plain")
          verify_header(sse_headers, "content-type", "text/event-stream")
          verify_header(sse_headers, "cache-control", "no-cache")
          verify_no_header(sse_headers, "content-length")
        end
      end

      def test_plugin_server_sent_events_each_message
        messages = [
          { event: "test", data: "test1", id: 1 },
          { event: "test", data: "test2", id: 2 },
          { comment: "this is a comment" },
          { event: "test", data: "test3" },
        ]
        session = HTTPX.plugin(:server_sent_events).with(ssl: { verify_hostname: false })
        start_test_servlet(SSE, tls: tls?, messages: messages) do |server|
          uri = "#{server.origin}/"

          response = session.get(uri, event_stream: true)
          messages = response.each_message.to_a
          assert messages.size == 3, "all the messages should have been yielded"
          assert(messages.all? { |m| m.event == "test" })
          assert messages[0].id == "1"
          assert messages[0].data == "test1"
          assert messages[1].id == "2"
          assert messages[1].data == "test2"
          assert messages[2].id.nil?
          assert messages[2].data == "test3"
        end
      end

      def test_plugin_server_sent_events_multiple_datas_concat_single_message
        messages = [
          { data: "test1" },
          { data: %w[test2 test3] },
        ]
        session = HTTPX.plugin(:server_sent_events).with(ssl: { verify_hostname: false })
        start_test_servlet(SSE, tls: tls?, messages: messages) do |server|
          uri = "#{server.origin}/"

          response = session.get(uri, event_stream: true)
          messages = response.each_message.to_a
          assert messages.size == 2, "all the messages should have been yielded"
          assert messages[0].data == "test1"
          assert messages[1].data == "test2\ntest3"
        end
      end

      def test_plugin_server_sent_events_retries_last_used_id
        return unless tls?

        messages = [
          { data: "test1", id: 1 },
          { data: "test2", id: 2 },
          { data: "test3", id: 3 },
        ]
        session = HTTPX.plugin(RequestInspector)
                       .plugin(:retries)
                       .plugin(:server_sent_events)
                       .with(ssl: { verify_hostname: false })
        start_test_servlet(SSE, tls: tls?, messages: messages, close_after: 2) do |server|
          uri = "#{server.origin}/"

          response = session.get(uri, event_stream: true)
          messages = response.each_message.to_a
          total_requests = session.total_requests

          # assert that there was an actual retry
          assert total_requests.size == 2
          first_request, retry_request = total_requests
          verify_no_header(first_request.headers, "last-event-id")
          verify_header(retry_request.headers, "last-event-id", "2")

          # assert that the messages before the retry aren't repeated
          assert messages.size == 3, "all the messages should have been yielded"
          assert messages[0].id == "1"
          assert messages[0].data == "test1"
          assert messages[1].id == "2"
          assert messages[1].data == "test2"
          assert messages[2].id == "3"
          assert messages[2].data == "test3"
        end
      end

      def test_plugin_server_sent_events_retries_last_used_id_retry_after
        return unless tls?

        messages = [
          { data: "test1", id: 1, retry: 2000 },
          { data: "test2", id: 2, retry: 2000 },
          { data: "test3", id: 3, retry: 2000 },
        ]
        session = HTTPX.plugin(RequestInspector).plugin(:retries).plugin(:server_sent_events).with(ssl: { verify_hostname: false })
        start_test_servlet(SSE, tls: tls?, messages: messages, close_after: 2) do |server|
          uri = "#{server.origin}/"

          before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          response = session.get(uri, event_stream: true)
          messages = response.each_message.to_a
          after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
          total_time = after_time - before_time
          total_requests = session.total_requests

          # assert that there was an actual retry
          assert total_requests.size == 2
          first_request, retry_request = total_requests
          verify_no_header(first_request.headers, "last-event-id")
          verify_header(retry_request.headers, "last-event-id", "2")

          verify_execution_delta(2, total_time, 1)

          # assert that the messages before the retry aren't repeated
          assert messages.size == 3, "all the messages should have been yielded"
          assert messages[0].id == "1"
          assert messages[0].data == "test1"
          assert messages[1].id == "2"
          assert messages[1].data == "test2"
          assert messages[2].data == "test3"
        end
      end
    end
  end
end
