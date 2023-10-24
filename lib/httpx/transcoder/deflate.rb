# frozen_string_literal: true

require "zlib"

module HTTPX
  module Transcoder
    module Deflate
      class Deflater < Transcoder::Deflater
        def deflate(chunk)
          @deflater ||= Zlib::Deflate.new

          if chunk.nil?
            unless @deflater.closed?
              last = @deflater.finish
              @deflater.close
              last.empty? ? nil : last
            end
          else
            @deflater.deflate(chunk)
          end
        end
      end

      class Inflater < Transcoder::Inflater
        def initialize(bytesize) # rubocop:disable Lint/MissingSuper
          @inflater = Zlib::Inflate.new(Zlib::MAX_WBITS * -1)
          super
        end
      end

      module_function

      def encode(body)
        Deflater.new(body)
      end

      def decode(response, bytesize: nil)
        bytesize ||= response.headers.key?("content-length") ? response.headers["content-length"].to_i : Float::INFINITY
        Inflater.new(bytesize)
      end
    end
  end
end
