# frozen_string_literal: true

module FaradayHelpers
  private

  # extra options to pass when building the adapter
  def adapter_options
    []
  end

  def faraday_connection(options = {}, &optional_connection_config_blk)
    return @faraday_connection if defined?(@faraday_connection)

    builder_block = proc do |b|
      b.request :url_encoded
      b.adapter :httpx, *adapter_options, &optional_connection_config_blk
    end

    options[:ssl] ||= {}
    options[:ssl][:ca_file] ||= ENV["SSL_FILE"]

    server = options.delete(:server_uri) || URI("https://#{httpbin}")

    @faraday_connection = Faraday::Connection.new(server.to_s, options, &builder_block).tap do |conn|
      conn.headers["X-Faraday-Adapter"] = "httpx"
      adapter_handler = conn.builder.handlers.last
      conn.builder.insert_before adapter_handler, Faraday::Response::RaiseError
    end
  end

  def request_headers(response)
    if response.is_a?(Hash)
      response[:request][:headers]
    else
      response.env.request_headers
    end.transform_keys(&:downcase)
  end

  def teardown
    super

    @faraday_connection.close if defined?(@faraday_connection)
  end
end
