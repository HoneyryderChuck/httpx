# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"
require "webmock/minitest"

class Bug_1_6_1_Test < Minitest::Test
  include HTTPHelpers

  def test_retries_should_retry_on_goaway_cancel
    start_test_servlet(GoawayCancelErrorServer) do |server|
      http = HTTPX.plugin(SessionWithPool)
                  .plugin(RequestInspector)
                  .plugin(:retries)
                  .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

      uri = "#{server.origin}/"
      response = http.get(uri)
      verify_status(response, 200)
      assert http.calls == 1, "expect request to be built 1 more time (was #{http.calls})"
      http.close
    end
  end

  class GoawayCancelErrorServer < TestHTTP2Server
    def initialize(**)
      @sent = Hash.new(false)
      super
    end

    private

    def handle_stream(conn, stream)
      if @cancelled
        super
      else
        conn.goaway(:cancel)
        @cancelled = true
      end
    end
  end
end
