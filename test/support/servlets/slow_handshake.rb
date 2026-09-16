# frozen_string_literal: true

require_relative "test"

# Holds off on accepting the first connection. The client's TCP connect completes into the listen
# backlog, but its TLS handshake cannot begin until the server accepts -- so from the client's side
# the handshake it is waiting on takes +handshake_delay+ seconds, which makes it measurable.
class SlowHandshakeServer < TestHTTP2Server
  def initialize(handshake_delay: 1, **kw)
    super(**kw)
    @handshake_delay = handshake_delay
    @accepted = false
  end

  private

  def handle_server(server)
    unless @accepted
      @accepted = true
      sleep @handshake_delay if @handshake_delay.positive?
    end

    super
  end
end
