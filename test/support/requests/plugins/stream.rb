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

        assert session.total_responses.size == 2, "there should be 2 available responses"
      end

      def test_plugin_stream_multiple_responses_error
        session = HTTPX.plugin(:stream)

        assert_raises(HTTPX::Error, /support only 1 response at a time/) do
          session.get(build_uri("/stream/2"), build_uri("/stream/3"), stream: true)
        end
      end

      def test_plugin_stream_each
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        lines = response.each.each_with_index.map do |line, idx|
          data = JSON.parse(line)
          assert data["id"] == idx
        end

        assert lines.size == 3, "all the lines should have been yielded"
      end

      def test_plugin_stream_each_line
        session = HTTPX.plugin(:stream)

        response = session.get(build_uri("/stream/3"), stream: true)
        lines = response.each_line.each_with_index.map do |line, idx|
          assert !line.end_with?("\n")
          data = JSON.parse(line)
          assert data["id"] == idx
        end

        assert lines.size == 3, "all the lines should have been yielded"
      end
    end
  end
end
