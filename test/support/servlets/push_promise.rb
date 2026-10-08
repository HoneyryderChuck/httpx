# frozen_string_literal: true

require_relative "test"

class PushPromiseServer < TestHTTP2Server
  using HTTPX::URIExtensions

  def initialize(num_promises: 1, **kw)
    super(**kw)
    @num_promises = num_promises
  end

  private

  def handle_request(conn, stream)
    return super if conn.remote_settings.settings_enable_push.zero?

    response = "PARENT"
    stream.headers({
                     ":status" => "200",
                     "content-length" => response.bytesize.to_s,
                     "content-type" => "text/plain",
                   }, end_stream: false)

    authority = URI(origin).authority
    push_streams = []
    @num_promises.times do |i|
      head = { ":method" => "GET",
               ":scheme" => "https",
               ":path" => "/#{i}",
               ":authority" => authority }

      stream.promise(head) do |push|
        child_response = "CHILD #{i}"
        push.headers({
                       ":status" => "200",
                       "content-type" => "text/plain",
                       "content-length" => child_response.bytesize.to_s,
                       "x-http2-push" => "1",
                     })
        push_streams << [push, child_response]
      end
    end

    stream.data(response)

    push_streams.each do |push, payload|
      push.data(payload)
    end
  end
end
