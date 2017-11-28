# frozen_string_literal: true

module HTTPX
  class Client
    def initialize(**options)
      @connection = Connection.new(**options)
      @default_options = options 
    end

    def request(verb, uri, **options)
      request = Request.new(verb, uri, **@default_options.merge(options))
    end

    def send(request)
      @connection << request
      @connection.process_events until response = @connection.response(request)
      response
    end
  end
end
