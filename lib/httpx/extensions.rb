# frozen_string_literal: true

require "uri"

module HTTPX
  module ArrayExtensions
    module FilterMap
      refine Array do
        # Ruby 2.7 backport
        def filter_map
          return to_enum(:filter_map) unless block_given?

          each_with_object([]) do |item, res|
            processed = yield(item)
            res << processed if processed
          end
        end
      end unless Array.method_defined?(:filter_map)
    end

    module Intersect
      refine Array do
        # Ruby 3.1 backport
        def intersect?(arr)
          if size < arr.size
            smaller = self
          else
            smaller, arr = arr, self
          end
          (arr & smaller).size > 0
        end
      end unless Array.method_defined?(:intersect?)
    end
  end

  module URIExtensions
    # uri 0.11 backport, ships with ruby 3.1
    refine URI::Generic do

      def non_ascii_hostname
        @non_ascii_hostname
      end

      def non_ascii_hostname=(hostname)
        @non_ascii_hostname = hostname
      end

      def authority
        return host if port == default_port

        "#{host}:#{port}"
      end unless URI::HTTP.method_defined?(:authority)

      def origin
        "#{scheme}://#{authority}"
      end unless URI::HTTP.method_defined?(:origin)

      def altsvc_match?(uri)
        uri = URI.parse(uri)

        origin == uri.origin || begin
          case scheme
          when "h2"
            (uri.scheme == "https" || uri.scheme == "h2") &&
            host == uri.host &&
            (port || default_port) == (uri.port || uri.default_port)
          else
            false
          end
        end
      end
    end
  end
end
