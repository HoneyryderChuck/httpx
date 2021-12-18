# frozen_string_literal: true

require "objspace"

unless ObjectSpace.method_defined?(:memsize_of_all)
  module ObjectSpace
    module_function

    def memsize_of_all(klass = false)
      total = 0
      total_mem = 0
      ObjectSpace.each_object(klass) do |e|
        total += 1
        total_mem += ObjectSpace.memsize_of(e)
      end
      [total, total_mem]
    end
  end
end

module ProfilerHelpers
  module_function

  def measure_time
    initial = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    yield
  ensure
    total = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - initial
    puts "Took #{total} milliseconds to run!"
  end

  def measure_rss
    rss_proc = lambda do
      ps_call = `ps -p #{Process.pid} -o rss -h`
      /\d+/.match(ps_call)[0].to_i
    end
    prev_rss = rss_proc.call

    yield
  ensure
    next_rss = rss_proc.call
    puts "Increase: rss -> #{next_rss - prev_rss} kylobytes"
  end

  def measure_mem_size
    httpx_classes = [
      HTTPX,
      HTTPX::Connection,
      HTTPX::Parser,
      HTTPX::Resolver,
    ].map { |klass| [klass, klass.constants.map { |cons| klass.const_get(cons) }] }
                    .flatten
                    .grep(Class)

    http2_next_classes = HTTP2Next.constants.map { |sym| HTTP2Next.const_get(sym) }.grep(Class)

    obj_memsize_proc = lambda do
      [*httpx_classes, *http2_next_classes, Hash, Array, String].to_h do |klass|
        count, size = ObjectSpace.memsize_of_all(klass)
        [klass, [count, size]]
      end
    end

    prev_memsize = obj_memsize_proc.call

    GC.start
    yield
  ensure
    GC.start

    next_memsize = obj_memsize_proc.call

    next_memsize.each do |klass, (count, size)|
      prev_count, prev_size = prev_memsize[klass]
      current_count = count - prev_count
      next if current_count.zero?

      current_size = size - prev_size
      puts "#{klass} -> objects: (#{current_count}), size: (#{current_size})"
    end
  end

  def measure_gc_stat
    prev_stat = GC.stat

    yield
  ensure
    next_stat = GC.stat
    next_stat.each do |k, v|
      puts "#{k}: #{prev_stat[k]} -> #{v}"
    end
  end

  def memory_profile(&block)
    require "memory_profiler"
    MemoryProfiler.report(allow_files: ["lib/httpx"], &block).pretty_print
  end
end
