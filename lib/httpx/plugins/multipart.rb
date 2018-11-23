# frozen_string_literal: true

module HTTPX
  module Plugins
    module Multipart
      module FormTranscoder
        module_function

        class Encoder
          extend Forwardable

          def_delegator :@raw, :content_type

          def_delegator :@raw, :to_s

          def_delegator :@raw, :read

          def initialize(form)
            @raw = HTTP::FormData.create(form)
          end

          def bytesize
            @raw.content_length
          end

          def force_encoding(*args)
            @raw.to_s.force_encoding(*args)
          end

          def to_str
            @raw.to_s
          end
        end

        def encode(form)
          Encoder.new(form)
        end
      end

      def self.load_dependencies(*)
        require "http/form_data"
      end

      def self.configure(*)
        Transcoder.register("form", FormTranscoder)
      end
    end
    register_plugin :multipart, Multipart
  end
end
