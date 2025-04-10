# frozen_string_literal: true

module ResponseHelpers
  private

  def verify_status(response, expect)
    raise response.error if response.is_a?(HTTPX::ErrorResponse)

    assert response.status == expect, "status assertion failed: #{response.status} (expected: #{expect})"
  end

  %w[header param].each do |meth|
    class_eval <<-DEFINE, __FILE__, __LINE__ + 1
      def verify_#{meth}(#{meth}s, key, expect)                                                                     # def verify_header(headers, key, expect)
        assert #{meth}s.key?(key), "#{meth}s don't contain the given key ('\#{key}', headers: \#{#{meth}s})"        #   assert headers.key?(key), "headers ...
        value = #{meth}s[key]                                                                                       #   value = headers[key]
        if value.respond_to?(:start_with?)                                                                          #   if value.respond_to?(:start_with?)
          assert value.start_with?(expect), "#{meth} assertion failed: \#{key}=\#{value} (expected: \#{expect}})"   #     assert value.start_with?(expect), "headers assertion failed:  ...
        else                                                                                                        #   else
          assert value == expect, "#{meth} assertion failed: \#{key}=\#{value.inspect} (expected: \#{expect.to_s})" #     assert value == expect, "headers assertion failed: ...
        end                                                                                                         #   end
      end                                                                                                           # end

      def verify_no_#{meth}(#{meth}s, key)                                                                          # def verify_no_header(headers, key)
        assert !#{meth}s.key?(key), "#{meth}s contains the given key (" + key + ": \#{#{meth}s[key].inspect})"      #   assert !headers.key?(key), "headers contains ...
      end                                                                                                           # end
    DEFINE
  end

  def verify_body_length(response, expect = response.headers["content-length"].to_i)
    len = response.body.to_s.bytesize
    assert len == expect, "length assertion failed: #{len} (expected: #{expect})"
  end

  def verify_execution_delta(expected, actual, delta = 0)
    delta += 3 # because of jitter

    delta += if RUBY_ENGINE == "truffleruby"
      # truffleruby has a hard time complying reliably with this delta when running in parallel. Therefore,
      # we give it a bit of leeway.
      20
    else
      # delta checks become very innacurate under multi-thread mode, and elapsed time. we give it some leeway too.
      3
    end

    assert_in_delta expected, actual, delta, "expected to have executed in #{expected} secs (actual: #{actual} secs)"
  end

  def data_base64(path)
    "data:application/octet-stream;base64" \
      ",#{Base64.strict_encode64(File.read(path))}"
  end

  def verify_uploaded(body, type, expect)
    assert body[type] == expect, "#{type} is unexpected: #{body[type]} (expected: #{expect})"
  end

  def verify_error_response(response, expectation = nil)
    assert response.is_a?(HTTPX::ErrorResponse), "expected an error response (instead got: #{response.inspect})"

    return unless expectation

    case expectation
    when Regexp
      assert response.error.message =~ expectation,
             "expected to match /#{expectation}/ in \"#{response.error.message}\""
    when String
      assert response.error.message.include?(expectation),
             "expected \"#{response.error.message}\" to include \"#{expectation}\""
    when Class
      assert response.error.is_a?(expectation) || response.error.cause.is_a?(expectation),
             "expected #{response.error} to be a #{expectation}"
    else
      raise "unexpected expectation (#{expectation})"
    end
  end

  # test files

  def verify_uploaded_image(body, key, mime_type, skip_verify_data: false)
    assert body.key?("files"), "there were no files uploaded"
    assert body["files"].key?(key), "there is no image in the file"
    # checking mime-type is a bit leaky, as httpbin displays the base64-encoded data
    return if skip_verify_data

    assert body["files"][key].start_with?("data:#{mime_type}"), "data was wrongly encoded (#{body["files"][key][0..64]})"
  end

  def fixture
    File.read(fixture_file_path, encoding: Encoding::BINARY)
  end

  def fixture_name
    File.basename(fixture_file_path)
  end

  def fixture_file_name
    "image.jpg"
  end

  def fixture_file_path
    File.join("test", "support", "fixtures", fixture_file_name)
  end

  def start_test_servlet(servlet_class, *args, **kwargs)
    server = servlet_class.new(*args, **kwargs)
    th = Thread.new { server.start }
    begin
      yield server
    ensure
      if server.respond_to?(:shutdown)
        server.shutdown

        begin
          Timeout.timeout(3) { th.join }
        rescue Timeout::Error
          th.kill
        end
      else
        th.kill
      end
    end
  end
end
