# frozen_string_literal: true

module HTTPX
  module Loggable
    COLORS = {
      black:   30,
      red:     31,
      green:   32,
      yellow:  33,
      blue:    34,
      magenta: 35,
      cyan:    36,
      white:   37,
    }.freeze

    def log(level: @options.debug_level, label: "", color: nil, &msg)
      return unless @options.debug
      return unless @options.debug_level >= level
      message = (+label << msg.call << "\n")
      message = "\e[#{COLORS[color]}m#{message}\e[0m" if color
      @options.debug << message
    end
  end
end
