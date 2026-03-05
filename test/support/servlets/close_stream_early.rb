# frozen_string_literal: true

# it'll close the first stream immediately on first data chunk received
class CloseStreamEarly < TestHTTP2Server
  attr_reader :chunks_per_stream

  def initialize(*)
    super
    @chunks_per_stream = Hash.new { |hs, k| hs[k] = [] }
  end

  private

  def handle_stream(conn, stream)
    stream.on(:data) do |chunk|
      @chunks_per_stream[stream.id] << chunk
    end

    return super unless stream.id == 1

    stream.once(:data) do
      response = "TRY AGAIN"

      stream.headers({
                       ":status" => "400",
                       "content-length" => response.bytesize.to_s,
                       "content-type" => "text/plain",
                     }, end_stream: false)
      stream.data(response, end_stream: true)
    end
  end
end
