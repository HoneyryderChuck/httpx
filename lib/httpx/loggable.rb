# frozen_string_literal: true

module HTTPX
  module Loggable
    COLORS = {
      black: 30,
      red: 31,
      green: 32,
      yellow: 33,
      blue: 34,
      magenta: 35,
      cyan: 36,
      white: 37,
    }.freeze

    def log(level: @options.debug_level, color: nil, &msg)
      return unless @options.debug
      return unless @options.debug_level >= level

      debug_stream = @options.debug

      message = (+"" << msg.call << "\n")
      message = "\e[#{COLORS[color]}m#{message}\e[0m" if color && debug_stream.respond_to?(:isatty) && debug_stream.isatty
      debug_stream << message
    end

    if Exception.instance_methods.include?(:full_message)

      def log_exception(ex, level: @options.debug_level, color: nil)
        return unless @options.debug
        return unless @options.debug_level >= level

        log(level: level, color: color) { ex.full_message }
      end

    else

      def log_exception(ex, level: @options.debug_level, color: nil)
        return unless @options.debug
        return unless @options.debug_level >= level

        message = +"#{ex.message} (#{ex.class})"
        message << "\n" << ex.backtrace.join("\n") unless ex.backtrace.nil?
        log(level: level, color: color) { message }
      end

    end
  end
end
