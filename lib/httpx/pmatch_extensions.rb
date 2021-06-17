# frozen_string_literal: true

module HTTPX
  module ResponsePatternMatchExtensions
    def deconstruct
      [@status, @headers, @body]
    end

    def deconstruct_keys(_keys)
      { status: @status, headers: @headers, body: @body }
    end
  end

  module ErrorResponsePatternMatchExtensions
    def deconstruct
      [@error]
    end

    def deconstruct_keys(_keys)
      { error: @error }
    end
  end

  module HeadersPatternMatchExtensions
    def deconstruct
      to_a
    end
  end

  Headers.include HeadersPatternMatchExtensions
  Response.include ResponsePatternMatchExtensions
  ErrorResponse.include ErrorResponsePatternMatchExtensions
end
