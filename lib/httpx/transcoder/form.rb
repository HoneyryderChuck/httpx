# frozen_string_literal: true

require "forwardable"
require "uri"
require_relative "multipart"

module HTTPX
  module Transcoder
    module Form
      module_function

      PARAM_DEPTH_LIMIT = 32

      class Encoder
        extend Forwardable

        def_delegator :@raw, :to_s

        def_delegator :@raw, :to_str

        def_delegator :@raw, :bytesize

        def initialize(form)
          @raw = form.each_with_object("".b) do |(key, val), buf|
            HTTPX::Transcoder.normalize_keys(key, val) do |k, v|
              buf << "&" unless buf.empty?
              buf << URI.encode_www_form_component(k)
              buf << "=#{URI.encode_www_form_component(v.to_s)}" unless v.nil?
            end
          end
        end

        def content_type
          "application/x-www-form-urlencoded"
        end
      end

      module Decoder
        module_function

        def call(response, *)
          URI.decode_www_form(response.to_s).each_with_object({}) do |(field, value), params|
            HTTPX::Transcoder.normalize_query(params, field, value, PARAM_DEPTH_LIMIT)
          end
        end
      end

      def encode(form)
        if multipart?(form)
          Multipart::Encoder.new(form)
        else
          Encoder.new(form)
        end
      end

      def decode(response)
        content_type = response.content_type.mime_type

        case content_type
        when "application/x-www-form-urlencoded"
          Decoder
        when "multipart/form-data"
          Multipart::Decoder.new(response)
        else
          raise Error, "invalid form mime type (#{content_type})"
        end
      end

      def multipart?(data)
        data.any? do |_, v|
          Multipart::MULTIPART_VALUE_COND.call(v) ||
            (v.respond_to?(:to_ary) && v.to_ary.any?(&Multipart::MULTIPART_VALUE_COND)) ||
            (v.respond_to?(:to_hash) && v.to_hash.any? { |_, e| Multipart::MULTIPART_VALUE_COND.call(e) })
        end
      end
    end
  end
end
