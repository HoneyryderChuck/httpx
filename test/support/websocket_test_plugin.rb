# frozen_string_literal: true

require "forwardable"
require "websocket/driver"

# have to roll our own, as the default client bundles its own
# HTTP client handshake logic
class WSDriver < WebSocket::Driver::Hybi
  include WebSocket

  def initialize(*, opts)
    h = opts.delete(:headers)
    super
    @headers = h

    @key = SecureRandom.base64(16)
    @headers["upgrade"]               = "websocket"
    @headers["connection"]            = "Upgrade"
    @headers["sec-websocket-key"]     = @key
    @headers["sec-websocket-version"] = VERSION

    @headers["Sec-WebSocket-Protocol"] = @protocols * ", " if @protocols.size.positive?

    extensions = @extensions.generate_offer
    @headers["Sec-WebSocket-Extensions"] = extensions if extensions
  end

  def start(bytes)
    open
    parse(bytes)
  end

  def validate(headers)
    accept     = headers["sec-websocket-accept"]
    protocol   = headers["sec-websocket-protocol"]

    return fail_handshake("Sec-WebSocket-Accept mismatch") unless accept == Driver::Hybi.generate_accept(@key)

    if protocol && !protocol.empty?
      return fail_handshake("Sec-WebSocket-Protocol mismatch") unless @protocols.include?(protocol)

      @protocol = protocol
    end

    begin
      @extensions.activate(@headers["Sec-WebSocket-Extensions"])
    rescue ::WebSocket::Extensions::ExtensionError => e
      return fail_handshake(e.message)
    end
    true
  end

  def fail_handshake(message)
    message = "Error during WebSocket handshake: #{message}"
    @ready_state = 3
    emit(:error, message)
    emit(:close, Driver::CloseEvent.new(Driver::Hybi::ERRORS[:protocol_error], message))
    false
  end
end

class WSCLient
  extend Forwardable

  def_delegator :@driver, :headers

  attr_reader :messages

  def initialize(io, headers)
    @io = io
    @closed = false
    @messages = []

    @driver = WSDriver.new(self, masking: true, headers: headers)
    @driver.on(:open)    { |_event| send("handshake") }
    @driver.on(:message) { |event| @messages << event.data }
    @driver.on(:error)   { |error| warn("ws error: #{error}") }
    @driver.on(:close)   { |event| finalize(event) }
  end

  def start(bytes)
    @driver.start(bytes)
    @thread = Thread.new do
      until @closed
        bytes = @io.read(1)
        @driver.parse(bytes)
      end
    end
  end

  def validate(*args)
    @driver.validate(*args)
  end

  def send(message)
    @driver.text(message)
  end

  def write(data)
    @io.write(data)
  end

  def close
    @driver.close
  end

  def finalize(_event)
    @closed = true
  end
end

module WSTestPlugin
  class << self
    def load_dependencies(klass)
      klass.plugin(:upgrade)
    end

    def call(connection, request, response)
      return unless (ws = request.websocket)

      return unless ws.validate(response.headers)

      connection.hijack_io
      response.websocket = ws
      ws.start(response.body.to_s)
    end

    def extra_options(options)
      options.merge(max_concurrent_requests: 1, upgrade_handlers: options.upgrade_handlers.merge("websocket" => self))
    end
  end

  module ConnectionMethods
    def send(request)
      request.init_websocket(self) unless request.websocket || @upgrade_protocol

      super
    end
  end

  module RequestMethods
    attr_reader :websocket

    def init_websocket(connection)
      if connection.state == :open
        socket = connection.to_io
        @websocket = WSCLient.new(socket, @headers)
      else
        connection.once(:open) do
          socket = connection.to_io
          @websocket = WSCLient.new(socket, @headers)
        end
      end
    end
  end

  module ResponseMethods
    attr_accessor :websocket
  end
end
