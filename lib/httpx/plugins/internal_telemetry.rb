# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # The InternalTelemetry plugin is for internal use only. It is therefore undocumented, and
    # its use is disencouraged, as API compatiblity will **not be guaranteed**.
    #
    # The gist of it is: when debug_level of logger is enabled to 3 or greater, considered internal-only
    # supported log levels, it'll be loaded by default.
    #
    # Against a specific point of time, which will be by default the session initialization, but can be set
    # by the end user in $http_init_time, different diff metrics can be shown. The "point of time" is calculated
    # using the monotonic clock.
    module InternalTelemetry
      module TrackTimeMethods
        private

        def elapsed_time
          yield
        ensure
          meter_elapsed_time("#{self.class.superclass}##{caller_locations(1, 1)[0].label}")
        end

        def meter_elapsed_time(label)
          $http_init_time ||= Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          prev_time = $http_init_time
          after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
          # $http_init_time = after_time
          elapsed = after_time - prev_time
          warn(+"\e[31m" << "[ELAPSED TIME]: #{label}: #{elapsed} (ms)" << "\e[0m")
        end
      end

      module InstanceMethods
        def self.included(klass)
          klass.prepend TrackTimeMethods
          super
        end

        def initialize(*)
          meter_elapsed_time("Session: initializing...")
          super
          meter_elapsed_time("Session: initialized!!!")
        end

        private

        def build_requests(*)
          elapsed_time { super }
        end

        def fetch_response(*)
          response = super
          meter_elapsed_time("Session -> response") if response
          response
        end

        def close(*)
          super
          meter_elapsed_time("Session -> close")
        end
      end

      module RequestMethods
        def self.included(klass)
          klass.prepend TrackTimeMethods
          super
        end

        def transition(nextstate)
          state = @state
          super
          meter_elapsed_time("Request[#{@verb} #{@uri}: #{state}] -> #{nextstate}") if nextstate == @state
        end
      end

      module ConnectionMethods
        def self.included(klass)
          klass.prepend TrackTimeMethods
          super
        end

        def transition(nextstate)
          state = @state
          super
          meter_elapsed_time("Connection[#{@origin}]: #{state} -> #{nextstate}") if nextstate == @state
        end
      end
    end
    register_plugin :internal_telemetry, InternalTelemetry
  end
end
