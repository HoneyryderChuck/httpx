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
    end
  end

  def request_headers(response)
    if response.is_a?(Hash)
      response[:request][:headers]
    else
      response.env.request_headers
    end.transform_keys(&:downcase)
  end

  def verify_http_error_span(span, status, error)
    assert span.get_tag("http.status_code") == status.to_s

    if status >= 500 || Gem::Version.new(DatadogHelpers::DATADOG_VERSION::STRING) >= Gem::Version.new("2.0.0")
      assert span.get_tag("error.type") == error
      assert span.status == 1
    else
      assert span.status.zero?
    end
  end

  def teardown
    super

    @faraday_connection.close if defined?(@faraday_connection)
  end
end
