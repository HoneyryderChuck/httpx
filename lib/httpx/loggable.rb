# frozen_string_literal: true

module HTTPX
  module Loggable
    def log(level: @options.debug_level, label: "", color: nil, &msg)
      return unless @options.debug
      return unless @options.debug_level >= level
      message = (+label << msg.call << "\n")
      @options.debug << message
    end
  end
end
