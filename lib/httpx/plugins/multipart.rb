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
      MULTIPART_VALUE_COND = lambda do |value|
        value.respond_to?(:read) ||
          (value.respond_to?(:to_hash) &&
            value.key?(:body) &&
            (value.key?(:filename) || value.key?(:content_type)))
      end

      class << self
        def normalize_keys(key, value, &block)
          Transcoder.normalize_keys(key, value, MULTIPART_VALUE_COND, &block)
        end

        def load_dependencies(*)
          # :nocov:
          begin
            unless defined?(HTTP::FormData)
              # in order not to break legacy code, we'll keep loading http/form_data for them.
              require "http/form_data"
              warn "httpx: http/form_data is no longer a requirement to use HTTPX :multipart plugin. See migration instructions under" \
                "https://honeyryderchuck.gitlab.io/httpx/wiki/Multipart-Uploads.html#notes. \n\n" \
                "If you'd like to stop seeing this message, require 'http/form_data' yourself."
            end
          rescue LoadError
          end
          # :nocov:
          require "httpx/plugins/multipart/encoder"
          require "httpx/plugins/multipart/decoder"
          require "httpx/plugins/multipart/part"
          require "httpx/plugins/multipart/mime_type_detector"
        end

        def configure(*)
          Transcoder.register("form", FormTranscoder)
        end
      end

      module FormTranscoder
        module_function

        def encode(form)
          if multipart?(form)
            Encoder.new(form)
          else
            Transcoder::Form::Encoder.new(form)
          end
        end

        def decode(response)
          return Transcoder::Form.decode(response) if response.headers["content-type"] == "application/x-www-form-urlencoded"

          Decoder.new(response)
        end

        def multipart?(data)
          data.any? do |_, v|
            MULTIPART_VALUE_COND.call(v) ||
              (v.respond_to?(:to_ary) && v.to_ary.any?(&MULTIPART_VALUE_COND)) ||
              (v.respond_to?(:to_hash) && v.to_hash.any? { |_, e| MULTIPART_VALUE_COND.call(e) })
          end
        end
      end
    end
    register_plugin :multipart, Multipart
  end
end
