# frozen_string_literal: true

module HTTPX
  module Utils
    module_function

    def parse_altsvc(altsvc)
      alt_uris, *params = altsvc.split(/ *; */)
      params = Hash[params.map { |field| field.split("=") }]
      alt_uris.split(/ *, */).each do |alt_uri|
        alt_proto, alt_uri = alt_uri.split("=")
        alt_uri = alt_uri[1..-2] if alt_uri.start_with?("\"") && alt_uri.end_with?("\"")
        alt_uri = URI.parse("#{alt_proto}://#{alt_uri}")
        yield(alt_uri, params)
      end
    end
  end
end
