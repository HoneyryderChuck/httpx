# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for passing `http-form_data` objects (like file objects) as "multipart/form-data";
    #
    #   HTTPX.post(URL, form: form: { image: HTTP::FormData::File.new("path/to/file")})
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Multipart-Uploads
    #
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
