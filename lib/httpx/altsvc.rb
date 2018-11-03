# frozen_string_literal: true

module HTTPX
  module AltSvc
    @altsvc_mutex = Mutex.new
    @altsvcs = Hash.new { |h, k| h[k] = [] }

    module_function

    def cached_altsvc(origin)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @altsvc_mutex.synchronize do
        lookup(origin, now)
      end
    end

    def cached_altsvc_set(origin, entry)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @altsvc_mutex.synchronize do
        return if @altsvcs[origin].any? { |altsvc| altsvc["origin"] == entry["origin"] }
        entry["TTL"] = Integer(entry["ma"]) + now if entry.key?("ma")
        @altsvcs[origin] << entry
        entry
      end
    end

    def lookup(origin, ttl)
      return [] unless @altsvcs.key?(origin)
      @altsvcs[origin] = @altsvcs[origin].select do |entry|
        !entry.key?("TTL") || entry["TTL"] > ttl
      end
      @altsvcs[origin].reject { |entry| entry["noop"] }
    end

    def emit(request, response)
      # Alt-Svc
      return unless response.headers.key?("alt-svc")
      origin = request.origin
      host = request.uri.host
      parse(response.headers["alt-svc"]) do |alt_origin, alt_params|
        alt_origin.host ||= host
        yield(alt_origin, origin, alt_params)
      end
    end

    def parse(altsvc)
      alt_origins, *alt_params = altsvc.split(/ *; */)
      alt_params = Hash[alt_params.map { |field| field.split("=") }]
      alt_origins.split(/ *, */).each do |alt_origin|
        alt_proto, alt_origin = alt_origin.split("=")
        alt_origin = alt_origin[1..-2] if alt_origin.start_with?("\"") && alt_origin.end_with?("\"")
        alt_origin = URI.parse("#{alt_proto}://#{alt_origin}")
        yield(alt_origin, alt_params)
      end
    end
  end
end
