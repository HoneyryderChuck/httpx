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

    USE_DEBUG_LOG = ENV.key?("HTTPX_DEBUG")

    def log(
      level: @options.debug_level,
      color: nil,
      debug_level: @options.debug_level,
      debug: @options.debug,
      &msg
    )
      return unless debug_level >= level

      debug_stream = debug || ($stderr if USE_DEBUG_LOG)

      return unless debug_stream

      klass = self.class

      until (class_name = klass.name)
        klass = klass.superclass
      end

      message = +"(pid:#{Process.pid}, " \
                 "tid:#{Thread.current.object_id}, " \
                 "fid:#{Fiber.current.object_id}, " \
                 "self:#{class_name}##{object_id}) "
      message << msg.call << "\n"
      message = "\e[#{COLORS[color]}m#{message}\e[0m" if color && debug_stream.respond_to?(:isatty) && debug_stream.isatty
      debug_stream << message
    end

    def log_exception(ex, level: @options.debug_level, color: nil, debug_level: @options.debug_level, debug: @options.debug)
      log(level: level, color: color, debug_level: debug_level, debug: debug) { ex.full_message }
    end

    def log_redact(text, should_redact = @options.debug_redact)
      return text.to_s unless should_redact

      "[REDACTED]"
    end
  end
end
