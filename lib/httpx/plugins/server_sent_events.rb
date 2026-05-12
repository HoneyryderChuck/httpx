# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin implements convenience methods for Server Sent Events streams.
    #
    # https://gitlab.com/os85/httpx/wikis/Server-Sent-Events
    #
    module ServerSentEvents
      Message = if RUBY_VERSION >= "3.2.0" # rubocop:disable Naming/ConstantName
        Data.define(:data, :event, :id, :retry_after) do
          def initialize(event: nil, id: nil, retry_after: nil, **kwargs)
            super
          end
        end
      else
        Struct.new(:data, :event, :id, :retry_after, keyword_init: true)
      end

      class << self
        def subplugins
          {
            retries: ServerSentEventsRetries,
          }
        end

        def load_dependencies(klass)
          klass.plugin(:stream)
        end
      end

      # adds support for the following options:
      #
      # :event_stream :: whether the request is a server-sent events text event stream (defaults to <tt>false</tt>).
      module OptionsMethods
        def option_event_stream(val)
          val
        end
      end

      module InstanceMethods
        def request(*args, **options)
          options[:stream] = true if options[:event_stream]

          super
        end

        def build_request(*)
          super.tap do |request|
            if request.options.event_stream
              request.headers["accept"] = "text/event-stream"
              request.headers["cache-control"] = "no-cache"
            end
          end
        end
      end

      module RequestMethods
        attr_accessor :last_server_sent_message

        def initialize(*)
          super

          @last_server_sent_message = nil
        end
      end

      module StreamResponseMethods
        # yields each event Message as the server emits them.
        def each_message(&block)
          return enum_for(__method__) unless block

          payload = {}

          each_line do |line|
            if line.empty?
              if payload[:comment]
                payload.clear
                next
              end

              next if payload.empty?

              message = Message.new(**payload)

              payload.clear

              @request.last_server_sent_message = message

              yield message
            else
              type, value = line.split(": ", 2)

              case type
              when "data"
                type = type.to_sym
                if payload.key?(type)
                  payload[type] << "\n" << value
                else
                  payload[type] = value
                end
              when "id", "event", "retry"
                type = type.to_sym
                raise_format_error(line) if payload.key?(type) || value.empty?

                type = :retry_after if type == :retry # avoid using keyword

                payload[type] = value
              else
                # skip if it's a comment
                if line.start_with?(":")
                  payload[:comment] = true
                  next
                end

                raise_format_error(line)
              end
            end
          end
        end

        private

        def raise_format_error(line)
          raise Error, "'#{line}': invalid or unsupported event stream format"
        end
      end

      module ServerSentEventsRetries
        module InstanceMethods
          private

          def prepare_to_retry(request, *)
            super

            last_message = request.last_server_sent_message

            return unless last_message && last_message.id

            request.headers["last-event-id"] = last_message.id
          ensure
            request.last_server_sent_message = nil
          end

          def when_to_retry(request, *)
            retry_after = request.last_server_sent_message&.retry_after

            retry_after / 1_000.0 if retry_after # original in milliseconds

            request.last_server_sent_message&.retry_after && super
          end
        end
      end
    end
    register_plugin(:server_sent_events, ServerSentEvents)
  end
end
