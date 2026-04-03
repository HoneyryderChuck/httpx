# frozen_string_literal: true

# it'll close the first stream immediately on first data chunk received
class CloseAfterXThenDelaySeconds < TestHTTP2Server
  def initialize(seconds_to_close: 2, delay: 2, **kw)
    super(**kw)
    @timers = []
    @delay = delay
    @sent_first = @can_delay = false
    @seconds_to_close = seconds_to_close
  end

  private

  def buffer_to_socket(sock, *)
    super
    return unless @sent_first

    close_socket(sock)
    @sent_first = false
    @can_delay = true
  end

  def handle_stream(_conn, stream)
    if @can_delay
      sleep(@delay)

      return super
    end

    stream.on(:half_close) do
      response = "OK"
      stream.headers({
                       ":status" => "200",
                       "content-length" => response.bytesize.to_s,
                       "content-type" => "text/plain",
                     }, end_stream: false)
      stream.data(response, end_stream: true)
      @sent_first = true
    end
  end
end
