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
          assert conn1.match?(uri, conn1.options), "connections should be the same and matchable"
          assert conn2.match?(uri, conn2.options), "connections should be the same and matchable"
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
          assert conn1.match?(uri, conn1.options), "connections should be the same and matchable"
          assert conn2.match?(uri, conn2.options), "connections should be the same and matchable"

          # check that only one of them is in the pool
          pool_connections = pool.connections
          assert pool_connections.size == 1
          assert pool_connections == [main_conn]
          assert main_conn.state == (scheme == "https://" ? :inactive : :closed)
          assert hedge_conn.state == :closed
        ensure
          http.close
        end
      end
    end
  end
end
