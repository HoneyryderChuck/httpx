# frozen_string_literal: true

# only allows a single concurrent stream to be processed at a time
class SingleStreamAtATimeServer < TestHTTP2Server
  private

  def new_http2_parser
    ::HTTP2::Server.new(settings_max_concurrent_streams: 1)
  end
end
