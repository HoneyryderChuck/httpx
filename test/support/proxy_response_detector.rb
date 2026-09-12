# frozen_string_literal: true

module ProxyResponseDetector
  module RequestMethods
    attr_writer :proxied

    def proxied?
      @proxied
    end
  end

  module ResponseMethods
    def proxied?
      @request.proxied?
    end
  end

  module ConnectionMethods
    attr_reader :connect_requests

    def initialize(*)
      super
      @connect_requests = []
    end

    def send(request)
      return super unless @options.respond_to?(:proxy) && @options.proxy

      request.proxied = true

      super
    end

    private

    def __http_on_connect(request, _)
      @connect_requests << request

      super
    end
  end
end
