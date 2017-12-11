# frozen_string_literal: true

require_relative "test_helper"

class HTTP1Test < Minitest::Spec
  include Requests
  include Head
  include Get
  include ChunkedGet
  include WithBody
  include WithChunkedBody 
  include Headers 
  include ResponseBody 
  include IO 


  
  private

  def build_uri(suffix="/")
    "#{origin}#{suffix || "/"}"
  end

  def origin
    "http://nghttp2.org/httpbin"
  end
end
