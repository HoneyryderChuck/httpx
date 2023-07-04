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
  end
end
