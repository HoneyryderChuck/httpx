# frozen_string_literal: true

module HTTPX
  module Plugins::Multipart
    module Part
      module_function

      def call(value)
        # take out specialized objects of the way
        if value.respond_to?(:filename) && value.respond_to?(:content_type) && value.respond_to?(:read)
          return [value, value.content_type, value.filename]
        end

        content_type = filename = nil

        if value.is_a?(Hash)
          content_type = value[:content_type]
          filename = value[:filename]
          value = value[:body]
        end

        value = value.open(:binmode => true) if value.is_a?(Pathname)

        if value.is_a?(File)
          filename ||= File.basename(value.path)
          content_type ||= MimeTypeDetector.call(value, filename) || "application/octet-stream"
          [value, content_type, filename]
        else
          [StringIO.new(value.to_s), "text/plain"]
        end
      end
    end
  end
end
