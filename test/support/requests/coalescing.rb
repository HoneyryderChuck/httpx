# frozen_string_literal: true

module Requests
  module Coalescing
    def test_connection_coalescing
      coalesced_origin = "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"
      HTTPX.plugin(SessionWithPool).wrap do |http|
        response1 = http.get(origin)
        verify_status(response1, 200)
        response2 = http.get(coalesced_origin)
        verify_status(response2, 200)
        # introspection time
        connections = http.connections
        assert connections.size == 2
        origins = connections.map(&:origins)
        assert origins.any? { |orgs| orgs.sort == [origin, coalesced_origin].sort },
               "connections for #{[origin, coalesced_origin]} didn't coalesce (expected connection with both origins (#{origins}))"

        assert http.pool.connections_counter == 1, "coalesced connection should not have been accounted for in the pool"

        unsafe_origin = URI(origin)
        unsafe_origin.scheme = "http"
        response3 = http.get(unsafe_origin)
        verify_status(response3, 200)

        # introspection time
        connections = http.connections
        assert connections.size == 3
        origins = connections.map(&:origins)
        refute origins.any?([origin]),
               "connection coalesced inexpectedly (expected connection with both origins (#{origins}))"
      end
    end

    def test_coalesce_should_not_leak_across_threads
      # https://gitlab.com/os85/httpx/-/issues/365
      uri = URI(build_uri("/get", "https://#{httpbin}"))
      coalesced_uri = URI(build_uri("/get", "https://#{ENV["HTTPBIN_COALESCING_HOST"]}"))
      q = Queue.new

      http = HTTPX.plugin(SessionWithPool).plugin(:persistent)

      registered_conns = Set[]
      http.define_singleton_method(:select_connection) do |conn, selector|
        registered_conns << [conn, selector]
        super(conn, selector)
      end

      http.singleton_class.class_eval do
        public(:get_current_selector)
      end

      th1 = Thread.start do
        q.pop
        res = http.get(coalesced_uri)
        verify_status(res, 200)
        http.get_current_selector
      end

      th2 = Thread.start do
        res = http.get(uri)
        verify_status(res, 200)
        sel = http.get_current_selector
        q << :done
        sel
      end

      th2_selector = th2.value
      th1_selector = th1.value

      conns = http.connections.select(&:open?)
      assert conns.size == 1
      conn = conns.first
      assert conn.current_session.nil?, "connection should have reset its session already"
      assert conn.current_selector.nil?, "connection should have reset its selector already"

      assert http.pool.connections_counter == 1, "connection"
      assert http.pool.connections.include?(conn)

      assert registered_conns.size == 2

      assert registered_conns.include?([conn, th1_selector])
      assert registered_conns.include?([conn, th2_selector])
    ensure
      http.close if defined?(http)
    end
  end
end
