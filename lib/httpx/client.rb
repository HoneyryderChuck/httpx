# frozen_string_literal: true

module HTTPX
  class Client
    def initialize(**options)
      @default_options = Options.new(options) 
      @connection = Connection.new(@default_options)
    end

    def close
      @connection.close
    end

    def request(verb, uri, **options)
      Request.new(verb, uri, **@default_options.merge(options))
    end

    def send(*requests)
      requests.each { |request| @connection << request }
      responses = []

      # guarantee ordered responses
      loop do
        request = requests.shift
        @connection.process_events until response = @connection.response(request)

        responses << response
        break if requests.empty?
      end
      requests.size == 1 ? responses.first : responses
    end
  end
end
