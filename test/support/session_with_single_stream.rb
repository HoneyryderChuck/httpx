# frozen_string_literal: true

#
# This module is used only to test transitions from a full HTTP/2 connection when it
# exhausts the number of streamss
#
module SessionWithSingleStream
  module ConnectionMethods
    def build_parser
      parser = super
      def parser.exhausted?
        @connection.active_stream_count.positive?
      end
      parser.instance_variable_set(:@max_requests, 10)
      connection = parser.instance_variable_get(:@connection)
      connection.max_streams = 1
      parser
    end
  end
end
