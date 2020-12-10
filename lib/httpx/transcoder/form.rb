# frozen_string_literal: true

require "forwardable"
require "uri"

module HTTPX::Transcoder
  module Form
    module_function

    class Encoder
      extend Forwardable

      def_delegator :@raw, :to_s

      def_delegator :@raw, :bytesize

      def initialize(form)
        @raw = form.each_with_object("".b) do |(key, val), buf|
          normalize_keys(key, val) do |k, v|
            buf << "&" unless buf.empty?
            buf << "#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v.to_s)}"
          end
        end
      end

      def content_type
        "application/x-www-form-urlencoded"
      end

      private

      def normalize_keys(key, value, &block)
        if value.respond_to?(:to_ary)
          if value.empty?
            block.call("#{key}[]", "")
          else
            value.to_ary.each do |element|
              normalize_keys("#{key}[]", element, &block)
            end
          end
        elsif value.respond_to?(:to_hash)
          value.to_hash.each do |child_key, child_value|
            normalize_keys("#{key}[#{child_key}]", child_value, &block)
          end
        else
          block.call(key.to_s, value)
        end
      end
    end

    def encode(form)
      Encoder.new(form)
    end
  end
  register "form", Form
end
