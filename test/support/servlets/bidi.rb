# frozen_string_literal: true

require_relative "test"

class Bidi < TestHTTP2Server
  private

  def handle_stream(_conn, stream)
    stream.on(:data) do |d|
      next if d.empty?

      # puts "SERVER: payload chunk: <<#{d}>>"
      data = JSON.parse(d)
      stream.data(JSON.dump({ processed: data }) << "\n", end_stream: false)
    end

    stream.on(:half_close) do
      stream.data("", end_stream: true)
    end

    stream.headers({
                     ":status" => "200",
                     "date" => Time.now.httpdate,
                     "content-type" => "application/x-ndjson",
                   }, end_stream: false)
  end
end
