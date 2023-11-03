# frozen_string_literal: true

require "test_helper"
require "support/http_helpers"

class Bug_1_1_1_Test < Minitest::Test
  include HTTPHelpers

  def test_conection_callbacks_fire_setup_once
    uri = build_uri("/get")

    connected = 0

    HTTPX.on_connection_opened { |*| connected += 1 }
         .on_connection_closed { |*| connected -= 1 }
         .wrap do |session|
      3.times.each do
        response = session.get(uri)
        verify_status(response, 200)
        assert connected.zero?
      end
    end
  end

  private

  def scheme
    "http://"
  end
end
