# frozen_string_literal: true

require_relative "test"

# Delays processing the client's connection preface, and therefore the server SETTINGS frame which
# answers it, by +settings_delay+ seconds. TCP and TLS complete immediately; what the client then
# waits on is the HTTP/2 handshake alone, which is what makes it measurable separately.
class SlowSettingsServer < TestHTTP2Server
  def initialize(settings_delay: 1, **kw)
    super(**kw)
    @settings_delay = settings_delay
    @delayed = false
  end

  private

  def buffer_to_socket(sock, data)
    unless @delayed
      @delayed = true
      sleep @settings_delay if @settings_delay.positive?
    end

    super
  end
end
