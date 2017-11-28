# frozen_string_literal: true

module HTTPX
  class Request
    attr_reader :verb, :uri, :headers, :body

    def initialize(verb, uri, headers: {}, **options)
      @verb    = verb.to_s.downcase.to_sym
      @uri     = URI(uri)
      @headers = Headers.new(headers)
      @body    = nil
    end

    def path
      path = uri.path
      path << "/" if path.empty?
      path << "?#{uri.query}" if uri.query
      path
    end

    def <<(data)
      (@body ||= +"") << data
    end

    def authority
      host = @uri.host
      port_string = @uri.port == @uri.default_port ? nil : ":#{@uri.port}"
      "#{host}#{port_string}"
    end
  end
end
