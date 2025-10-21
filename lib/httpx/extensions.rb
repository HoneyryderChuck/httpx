# frozen_string_literal: true

require "uri"

module HTTPX
  module ArrayExtensions
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
    end
  end
end
