# frozen_string_literal: true

require_relative "test"

# HTTP/2 server (prior knowledge) which, once it receives half of the initial stream flow control
# window of request body, stops reading, and therefore stops sending WINDOW_UPDATE frames, until released.
class SlowWindowUpdateServer < TestHTTP2Server
  # not a multiple of the request body chunk size, so that the chunk exhausting the window
  # is only partially sent.
  WINDOW = 20_000

  attr_reader :received

  def initialize(*, **)
    super
    @unstalled = false
    @received = 0
    @stalled = Thread::Queue.new
    @released = Thread::Queue.new
  end

  def wait_until_stalled
    @stalled.pop
  end

  def release
    @released << true
  end

  private

  def new_http2_parser
    HTTP2::Server.new(settings_initial_window_size: WINDOW)
  end

  def handle_stream(_sock, conn, stream)
    super
    stream.on(:data) { |data| @received += data.bytesize }
  end

  def buffer_to_socket(sock, data)
    if !@unstalled && @received >= WINDOW / 2
      @unstalled = true
      @stalled << nil
      @released.pop
    end

    super
  end

  def shutdown
    @released << true
    super
  end
end
