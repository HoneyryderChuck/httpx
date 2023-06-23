# frozen_string_literal: true

module Requests
  module Plugins
    module Stream
      def test_plugin_stream
        session = HTTPX.plugin(RequestInspector).plugin(:stream)

        uri = build_uri("/get")

        no_stream_response = session.get(uri)
        stream_response = session.get(uri, stream: true)

        assert session.total_responses.size == 1, "there should be an available response"

        assert no_stream_response.to_s == stream_response.to_s, "content should be the same"

        assert stream_response.respond_to?(:headers) # test respond_to_missing?

        no_stream_headers = no_stream_response.headers.to_h
        no_stream_headers.delete("date")
        stream_headers = no_stream_response.headers.to_h
        stream_headers.delete("date")

        assert no_stream_headers == stream_headers, "headers should be the same " \
                                                    "(h1: #{no_stream_response.headers}, " \
                                                    "(h2: #{stream_response.headers}) "

        assert session.total_responses.size == 2, "there should be 2 available responses"
      end

      def test_plugin_stream_each
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        payload = response.each.to_a.join
        assert payload.lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_each_line
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        lines = response.each_line.with_index.map do |line, idx|
          assert !line.end_with?("\n")
          data = JSON.parse(line)
          assert data["id"] == idx
        end

        assert lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_multiple_responses_error
        session = HTTPX.plugin(:stream)

        assert_raises(HTTPX::Error, /support only 1 response at a time/) do
          response = session.get(build_uri("/stream/2"), build_uri("/stream/3"), stream: true)
          # force request
          response.each_line.to_a
        end
      end

      def test_plugin_stream_response_error
        session = HTTPX.plugin(:stream)

        assert_raises(HTTPX::HTTPError) do
          response = session.get(build_uri("/status/404"), stream: true)
          # force request
          response.each_line.to_a
        end
      end

      def test_plugin_stream_connection_error
        session = HTTPX.with_timeout(total_timeout: 1).plugin(:stream)

        assert_raises(HTTPX::TimeoutError) do
          response = session.get(build_uri("/delay/10"), stream: true)
          # force request
          response.each_line.to_a
        end
      end
    end
  end
end
