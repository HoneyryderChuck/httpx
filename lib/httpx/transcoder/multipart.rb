# frozen_string_literal: true

require_relative "multipart/encoder"
require_relative "multipart/decoder"
require_relative "multipart/part"
require_relative "multipart/mime_type_detector"

module HTTPX::Transcoder
  module Multipart
    MULTIPART_VALUE_COND = lambda do |value|
      value.respond_to?(:read) ||
        (value.respond_to?(:to_hash) &&
          value.key?(:body) &&
          (value.key?(:filename) || value.key?(:content_type)))
    end

    module_function

    def multipart?(form_data)
      form_data.any? do |_, v|
        Multipart::MULTIPART_VALUE_COND.call(v) ||
          (v.respond_to?(:to_ary) && v.to_ary.any?(&Multipart::MULTIPART_VALUE_COND)) ||
          (v.respond_to?(:to_hash) && v.to_hash.any? { |_, e| Multipart::MULTIPART_VALUE_COND.call(e) })
      end
    end

    def encode(form_data)
      Encoder.new(form_data)
    end
  end
end
