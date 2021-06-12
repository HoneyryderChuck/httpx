# frozen_string_literal: true

module HTTPX
  module ResponsePatternMatchExtensions
    def deconstruct
      [@status, @headers.to_h, @body]
    end

    def deconstruct_keys(_keys)
      { status: @status, headers: @headers.to_h, body: @body }
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

  Response.include ResponsePatternMatchExtensions
  ErrorResponse.include ErrorResponsePatternMatchExtensions
end
