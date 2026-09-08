# frozen_string_literal: true

class CloseAfterXRequests < TestHTTP2Server
  def initialize(requests_to_process: 1, **kw)
    super(**kw)
    @num_requests = @requests_to_process = requests_to_process
  end

  private

  def handle_stream(conn, stream)
    response = "".b

    stream.on(:data) do |data|
      response << data
    end

    stream.on(:half_close) do
      stream.headers({
                       ":status" => "200",
                       "content-length" => response.bytesize.to_s,
                       "content-type" => "text/plain",
                     }, end_stream: false)
      stream.data(response, end_stream: true)
      @num_requests -= 1

      if @num_requests.zero?
        conn.goaway
        @num_requests = @requests_to_process
      end
    end
  end
end
