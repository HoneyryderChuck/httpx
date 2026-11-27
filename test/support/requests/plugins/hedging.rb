# frozen_string_literal: true

module Requests
  module Plugins
    module Hedging
      module KeepHedgeConnections
        module InstanceMethods
          def connections_and_hedge
            connections.flat_map do |conn|
              [conn, conn.deleted_hedge_connection]
            end.compact.uniq
          end
        end

        module ConnectionMethods
          attr_reader :deleted_hedge_connection

          def hedge_connection=(conn)
            return super unless conn.nil? # rubocop:disable Lint/ReturnInVoidContext

            @deleted_hedge_connection = @hedge_connection

            super
          end
        end
      end

      def test_hedging_multiple_connections
        uri = URI(build_uri("/get"))
        HTTPX.plugin(SessionWithPool)
             .plugin(:hedging)
             .plugin(KeepHedgeConnections).wrap do |http|
          response = http.get(uri)

          verify_status(response, 200)

          connections = http.connections_and_hedge

          assert connections.size == 2
          conn1, conn2 = connections

          # check that both connections do not share the IO object
          assert !conn1.io.nil?
          assert !conn2.io.nil?
          assert conn1.io != conn2.io, "there should be two different sockets"
          # check that both connections are the same in everything else
          assert conn1.origins == conn2.origins
          assert conn1.addresses == conn2.addresses
          assert_only_main_connection_matches(connections, uri)
        end
      end

      def test_hedging_delay_before_new_connection
        uri = URI(build_uri("/get"))
        delay_uri = build_uri("/delay/6")

        http = HTTPX.plugin(SessionWithPool)
                    .plugin(:hedging, hedge_after: 4)
                    .plugin(KeepHedgeConnections)

        response = http.get(uri)

        verify_status(response, 200)

        connections = http.connections_and_hedge
        assert connections.size == 1

        http.connections.clear
        http.pool.connections.clear

        response = http.get(delay_uri)
        verify_status(response, 200)

        connections = http.connections_and_hedge

        assert connections.size == 2
        conn1, conn2 = connections

        # check that both connections do not share the IO object
        assert !conn1.io.nil?
        assert !conn2.io.nil?
        assert conn1.io != conn2.io, "there should be two different sockets"
        # check that both connections are the same in everything else
        assert conn1.origins == conn2.origins
        assert conn1.addresses == conn2.addresses
        assert_only_main_connection_matches(connections, uri)
      end

      {
        "string" => ->(payload) { payload },
        "stringio" => ->(payload) { StringIO.new(payload) },
        "file" => lambda { |payload|
          Tempfile.new("hedging").tap do |f|
            f.write(payload)
            f.flush
            f.rewind
          end
        },
      }.each do |mode, build_body|
        define_method :"test_hedging_slow_request_completes_with_hedge_#{mode}" do
          payload = "x" * 200_000
          body = build_body.call(payload)

          start_test_servlet(HedgingServer, tls: tls?, first_delay: 5) do |server|
            http = HTTPX.plugin(SessionWithPool)
                        .plugin(:hedging, hedge_after: 0.25)
                        .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

            response, elapsed = timed { http.post("#{server.origin}/#{mode}", body: body) }

            verify_status(response, 200)
            assert elapsed < 4, "hedge should have answered before the stalled request (took #{elapsed}s)"
            assert_hedge_received(response, payload)

            if mode == "file"
              hedged_file = response.request.raw_body
              assert !hedged_file.equal?(body), "the hedge should read the file through its own handle"
              assert hedged_file.closed?, "the hedge's file handle should be closed once it's done"
              assert !body.closed?, "the caller's file should be left open"
            end
          end
        ensure
          body.close! if body.is_a?(Tempfile)
        end
      end

      def test_hedging_persistent_open_connection
        payload = "x" * 200_000

        start_test_servlet(HedgingServer, tls: tls?, first_delay: 5) do |server|
          HTTPX.plugin(:persistent)
               .plugin(:hedging, hedge_after: 0.25)
               .with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
               .wrap do |http|
            # opens the connection.
            verify_status(http.get("#{server.origin}/warmup"), 200)

            response, elapsed = timed { http.post("#{server.origin}/upload", body: StringIO.new(payload)) }

            verify_status(response, 200)
            assert elapsed < 4, "hedge should have answered before the stalled request (took #{elapsed}s)"
            assert_hedge_received(response, payload)

            next_response, next_elapsed = timed { http.get("#{server.origin}/fast/next") }

            verify_status(next_response, 200)
            # 0.5 instead of 0.25 just to be lenient under multithread load
            assert next_elapsed < 0.5, "next request should not queue behind the stalled one (took #{next_elapsed}s)"
            assert json_body(next_response)["client_port"] == json_body(response)["client_port"],
                   "next request should reuse the faster connection"
          end
        end
      end

      def test_hedging_error_does_not_win_over_in_flight_hedge
        start_test_servlet(HedgingServer, tls: tls?, first_delay: 1, hedge_delay: 1.5, drop_first: true) do |server|
          http = HTTPX.plugin(:hedging, hedge_after: 0.25).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          response = http.post("#{server.origin}/upload", body: "payload")

          verify_status(response, 200)
          assert_hedge_received(response, "payload")
        end
      end

      # a multipart part which can't be copied, as it isn't backed by a file path.
      class CustomPart
        def filename
          "custom.txt"
        end

        def content_type
          "text/plain"
        end

        def size
          0
        end

        def read(*); end
      end

      {
        "string" => [true, ->(_) { { body: "payload" } }],
        "stringio" => [true, ->(_) { { body: StringIO.new("payload") } }],
        "file" => [true, ->(file) { { body: File.open(file.path) } }],
        "array" => [true, ->(_) { { body: %w[a b] } }],
        "form" => [true, ->(_) { { form: { "foo" => "bar" } } }],
        "json" => [true, ->(_) { { json: { "foo" => "bar" } } }],
        "deflated" => [true, ->(_) { { headers: { "content-encoding" => "gzip" }, body: "payload" } }],
        "enumerator" => [false, ->(_) { { body: %w[a b].each } }],
        "multipart" => [true, ->(file) { { form: { "field" => "value", "file" => File.open(file.path) } } }],
        "multipart_custom_part" => [false, ->(_) { { form: { "file" => CustomPart.new } } }],
        "unlinked_tempfile" => [false, ->(_) { { body: Tempfile.new("hedging-unlinked").tap { |f| f.write("payload") && f.unlink } } }],
      }.each do |name, (replayable, build_params)|
        define_method :"test_hedging_replayable_body_#{name}" do
          file = Tempfile.new("hedging")
          file.write("payload")
          file.flush

          request = HTTPX.plugin(:hedging).build_request("POST", "http://example.com/", build_params.call(file))

          assert request.body.replayable? == replayable, "expected replayable? to be #{replayable}"
        ensure
          file.close!
        end
      end

      def test_hedging_skips_bodies_that_cannot_be_replayed
        start_test_servlet(HedgingServer, tls: tls?, first_delay: 1) do |server|
          http = HTTPX.plugin(:hedging, hedge_after: 0.25).with(ssl: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

          response = http.post("#{server.origin}/stream", body: %w[a b c].each)

          verify_status(response, 200)
          body = json_body(response)
          assert body["first"], "body enumerators can't be duplicated, so no hedge should have been sent"
          assert body["sha256"] == Digest::SHA256.hexdigest("abc")
        end
      end

      def test_hedging_persistent_do_not_retain_hedge_connections
        uri = URI(build_uri("/get"))

        begin
          http = HTTPX.plugin(SessionWithPool)
                      .plugin(:persistent)
                      .plugin(:hedging)
                      .plugin(KeepHedgeConnections)

          response = http.get(uri)

          verify_status(response, 200)

          pool = http.pool
          connections = http.connections_and_hedge

          assert connections.size == 2
          conn1, conn2 = connections
          hedge_conn, main_conn = connections.partition(&:is_hedge_connection).map(&:first)

          # check that both connections do not share the IO object
          assert !conn1.io.nil?
          assert !conn2.io.nil?
          assert conn1.io != conn2.io, "there should be two different sockets"
          # check that both connections are the same in everything else
          assert conn1.origins == conn2.origins
          assert conn1.addresses == conn2.addresses
          assert_only_main_connection_matches(connections, uri)

          # check that only one of them is in the pool
          pool_connections = pool.connections
          assert pool_connections.size == 1
          assert pool_connections == [main_conn]
          assert main_conn.state == (scheme == "https://" ? :inactive : :closed)
          assert_includes(%i[idle closed], hedge_conn.state)
        ensure
          http.close
        end
      end

      private

      def assert_only_main_connection_matches(connections, uri)
        hedge_conns, main_conns = connections.partition(&:is_hedge_connection)
        assert main_conns.size == 1 && hedge_conns.size == 1
        assert main_conns.first.match?(uri, main_conns.first.options), "main connection should take new requests"
        assert !hedge_conns.first.match?(uri, hedge_conns.first.options), "hedge connection should not take new requests"
      end

      def timed
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        [result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
      end

      def assert_hedge_received(response, payload)
        body = json_body(response)
        assert !body["first"], "expected the hedged request to answer"
        assert body["bytes"] == payload.bytesize, "hedge sent #{body["bytes"]} of #{payload.bytesize} bytes"
      end
    end
  end
end
