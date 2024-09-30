# frozen_string_literal: true

require_relative "test_helper"

class PoolTest < Minitest::Test
  include HTTPHelpers
  include HTTPX

  using URIExtensions

  def test_pool_max_connections_per_origin
    uri = URI(build_uri("/"))
    responses = []
    q = Queue.new
    mtx = Thread::Mutex.new

    pool = Pool.new(max_connections_per_origin: 2)
    def pool.connections
      @connections
    end

    def pool.origin_counters
      @origin_counters
    end
    ths = 3.times.map do |_i|
      Thread.start do
        HTTPX.with(pool_options: { max_connections_per_origin: 2, pool_timeout: 30 }) do |http|
          http.instance_variable_set(:@pool, pool)
          response = http.get(uri)
          mtx.synchronize { responses << response }
          q.pop
        end
      end
    end

    not_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until (now = Process.clock_gettime(Process::CLOCK_MONOTONIC)) > not_after || q.num_waiting == 2
      ths.first(&:alive?).join(not_after - now)
    end

    assert pool.connections.empty?, "thread sessions should still be holding to the connections"
    assert pool.origin_counters[uri.origin] <= 2

    3.times { q << :done }
    ths.each(&:join)

    assert responses.size == 3
    responses.each do |res|
      verify_status(res, 200)
    end
  end

  def test_pool_pool_timeout
    uri = URI(build_uri("/"))
    q = Queue.new
    Thread::Mutex.new

    pool = Pool.new(max_connections_per_origin: 2, pool_timeout: 1)

    ths = 3.times.map do |_i|
      Thread.start do
        res = nil
        HTTPX.with(pool_options: { max_connections_per_origin: 2, pool_timeout: 1 }) do |http|
          begin
            http.instance_variable_set(:@pool, pool)
            res = http.get(uri).tap { q.pop }
          rescue StandardError => e
            res = e
          end
        end
        res
      end
    end

    not_after = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until (now = Process.clock_gettime(Process::CLOCK_MONOTONIC)) > not_after || q.num_waiting == 2
      ths.first(&:alive?).join(not_after - now)
    end
    sleep 1
    3.times { q << :done }
    ths.each(&:join)

    results = ths.map(&:value)

    assert(results.one?(ErrorResponse))
    err_res = results.find { |r| r.is_a?(ErrorResponse) }
    verify_error_response(err_res, PoolTimeoutError)
  end

  private

  def origin(orig = httpbin)
    "https://#{orig}"
  end
end
