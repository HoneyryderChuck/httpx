# frozen_string_literal: true

require_relative "support/http_test"

class HTTP2Test < HTTPTest
  include Requests
  include Get
  include Head
  include WithBody
  include Headers 
  include ResponseBody 
  include IO 

  include Plugins::FollowRedirects

  private

  def origin
    "https://nghttp2.org/httpbin"
  end
end
