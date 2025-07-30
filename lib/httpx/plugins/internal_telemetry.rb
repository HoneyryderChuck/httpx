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
      DEBUG_LEVEL = 3

      def self.extra_options(options)
        options.merge(debug_level: 3)
      end

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
          # klass = self.class

          # until (class_name = klass.name)
          #   klass = klass.superclass
          # end
          log(
            level: DEBUG_LEVEL,
            color: :red,
            debug_level: @options ? @options.debug_level : DEBUG_LEVEL,
            debug: nil
          ) do
            "[ELAPSED TIME]: #{label}: #{elapsed} (ms)" << "\e[0m"
          end
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

        def close(*)
          super
          meter_elapsed_time("Session -> close")
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

        def coalesce_connections(conn1, conn2, selector, *)
          result = super

          meter_elapsed_time("Connection##{conn2.object_id} coalescing to Connection##{conn1.object_id}") if result

          result
        end
      end

      module PoolMethods
        def self.included(klass)
          klass.prepend Loggable
          klass.prepend TrackTimeMethods
          super
        end

        def checkin_connection(connection)
          super.tap do
            meter_elapsed_time("Pool##{object_id}: checked in connection for Connection##{connection.object_id}[#{connection.origin}]}")
          end
        end
      end
    end
    register_plugin :internal_telemetry, InternalTelemetry
  end
end
