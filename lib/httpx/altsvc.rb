# frozen_string_literal: true

require "strscan"

module HTTPX
  module AltSvc
    @altsvc_mutex = Mutex.new
    @altsvcs = Hash.new { |h, k| h[k] = [] }

    module_function

    def cached_altsvc(origin)
      now = Utils.now
      @altsvc_mutex.synchronize do
        lookup(origin, now)
      end
    end

    def cached_altsvc_set(origin, entry)
      now = Utils.now
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
      return unless response.respond_to?(:headers)
      # Alt-Svc
      return unless response.headers.key?("alt-svc")

      origin = request.origin
      host = request.uri.host

      altsvc = response.headers["alt-svc"]

      # https://tools.ietf.org/html/rfc7838#section-3
      # A field value containing the special value "clear" indicates that the
      # origin requests all alternatives for that origin to be invalidated
      # (including those specified in the same response, in case of an
      # invalid reply containing both "clear" and alternative services).
      if altsvc == "clear"
        @altsvc_mutex.synchronize do
          @altsvcs[origin].clear
        end

        return
      end

      parse(altsvc) do |alt_origin, alt_params|
        alt_origin.host ||= host
        yield(alt_origin, origin, alt_params)
      end
    end

    def parse(altsvc)
      return enum_for(__method__, altsvc) unless block_given?

      scanner = StringScanner.new(altsvc)
      until scanner.eos?
        alt_service = scanner.scan(/[^=]+=("[^"]+"|[^;,]+)/)

        alt_params = []
        loop do
          alt_param = scanner.scan(/[^=]+=("[^"]+"|[^;,]+)/)
          alt_params << alt_param.strip if alt_param
          scanner.skip(/;/)
          break if scanner.eos? || scanner.scan(/ *, */)
        end
        alt_params = Hash[alt_params.map { |field| field.split("=") }]

        alt_proto, alt_authority = alt_service.split("=")
        alt_origin = parse_altsvc_origin(alt_proto, alt_authority)
        return unless alt_origin

        yield(alt_origin, alt_params.merge("proto" => alt_proto))
      end
    end

    def parse_altsvc_scheme(alt_proto)
      case alt_proto
      when "h2c"
        "http"
      when "h2"
        "https"
      end
    end

    def parse_altsvc_origin(alt_proto, alt_origin)
      alt_scheme = parse_altsvc_scheme(alt_proto) or return
      alt_origin = alt_origin[1..-2] if alt_origin.start_with?("\"") && alt_origin.end_with?("\"")

      URI.parse("#{alt_scheme}://#{alt_origin}")
    end
  end
end
