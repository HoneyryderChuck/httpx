# frozen_string_literal: true

module Loggable
  def log(level = @options.debug_level, label = "", &msg)
    return unless @options.debug
    return unless @options.debug_level >= level
    @options.debug << (+label << msg.call << "\n")
  end
end
