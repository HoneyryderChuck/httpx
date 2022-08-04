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
    def send(request)
      return super unless @options.respond_to?(:proxy) && @options.proxy

      proxy_uri = URI(@options.proxy.uri)

      request.proxied = @origin.host == proxy_uri.host && @origin.port == proxy_uri.port

      super
    end
  end
end
