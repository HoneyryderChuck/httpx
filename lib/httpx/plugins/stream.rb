# frozen_string_literal: true

module HTTPX
  module Plugins
    module Stream
      module InstanceMethods
        def stream
          headers("accept" => "text/event-stream",
                  "cache-control" => "no-cache")
        end
      end

      module ResponseMethods
        def complete?
          super ||
            stream? &&
              @stream_complete
        end

        def stream?
          @headers["content-type"].start_with?("text/event-stream")
        end

        def <<(data)
          res = super
          @stream_complete = true if String(data).end_with?("\n\n")
          res
        end
      end
    end
    register_plugin :stream, Stream
  end
end
