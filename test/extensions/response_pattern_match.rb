# frozen_string_literal: true

module ResponsePatternMatchTests
  include HTTPX

  def test_response_headers_deconstruct
    response = Response.new(request, 200, "2.0", { "host" => "google.com", "content-type" => "application/json" })
    case response
    in [_, [*, ["content-type", content_type], *], _]
      assert content_type == "application/json"
    else
      raise "unexpected response"
    end
  end

  def test_response_deconstruct
    response_with_body = Response.new(request, 200, "2.0", { "x-with-body" => "true" })
    response_with_body << "OK"

    responses = [
      response_with_body,
      Response.new(request, 202, "2.0", { "x-success" => "true" }),
      Response.new(request, 400, "2.0", { "x-client-error" => "true" }),
      Response.new(request, 500, "2.0", { "x-server-error" => "true" }),
      ErrorResponse.new(request, StandardError.new("match error")),
    ]

    responses.each do |response|
      case response
      in [200, headers, "OK"]
        verify_header(headers, "x-with-body", "true")
      in [201..399, headers, _body]
        verify_header(headers, "x-success", "true")
      in [400..499, headers, _body]
        verify_header(headers, "x-client-error", "true")
      in [500.., headers, _body]
        verify_header(headers, "x-server-error", "true")
      in [StandardError => error]
        assert error.message == "match error", "unexpected message (was '#{error.message}')"
      else
        raise "unexpected response: #{response}"
      end
    end
  end

  def test_response_deconstruct_keys
    response_with_body = Response.new(request, 200, "2.0", { "x-with-body" => "true" })
    response_with_body << "OK"

    responses = [
      response_with_body,
      Response.new(request, 202, "2.0", { "x-success" => "true" }),
      Response.new(request, 400, "2.0", { "x-client-error" => "true" }),
      Response.new(request, 500, "2.0", { "x-server-error" => "true" }),
      ErrorResponse.new(request, StandardError.new("match error")),
    ]

    responses.each do |response|
      case response
      in { status: 200, headers:, body: "OK" }
        verify_header(headers, "x-with-body", "true")
      in { status: 201..399, headers: }
        verify_header(headers, "x-success", "true")
      in { status: 400..499, headers: }
        verify_header(headers, "x-client-error", "true")
      in { status: 500.., headers: }
        verify_header(headers, "x-server-error", "true")
      in { error: error }
        assert error.message == "match error", "unexpected message (was '#{error.message}')"
      else
        raise "unexpected response: #{response}"
      end
    end
  end
end
