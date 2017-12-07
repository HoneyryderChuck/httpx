# frozen_string_literal: true

module HTTPX
  module Chainable
    def head(uri, **options)
      request(:head, uri, **options)
    end

    def get(uri, **options)
      request(:get, uri, **options)
    end

    def post(uri, **options)
      request(:post, uri, **options)
    end

    def put(uri, **options)
      request(:put, uri, **options)
    end

    def delete(uri, **options)
      request(:delete, uri, **options)
    end

    def trace(uri, **options)
      request(:trace, uri, **options)
    end

    def options(uri, **options)
      request(:options, uri, **options)
    end

    def connect(uri, **options)
      request(:connect, uri, **options)
    end

    def patch(uri, **options)
      request(:patch, uri, **options)
    end

    def request(verb, uri, **options)
      branch(**options).request(verb, uri)
    end

    def timeout(klass, **options)
      branch(timeout: Timeout.by(klass, **options))
    end

    def headers(headers)
      branch(default_options.with_headers(headers))
    end

    def encoding(encoding)
      branch(default_options.with_encoding(encoding))
    end

    def accept(type)
      headers("accept" => String(type)) 
    end

    private

    # :nodoc:
    def branch(options)
      Client.new(options)
    end
  end
end

