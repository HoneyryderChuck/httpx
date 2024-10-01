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

      request.proxied = true

      super
    end
  end
end
