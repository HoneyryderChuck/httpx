# frozen_string_literal: true

module HTTPX
  module Plugins
    # This plugin implements a session that persists connections over the duration of the process.
    #
    # This will improve connection reuse in a long-running process.
    #
    # One important caveat to note is, although this session might not close connections,
    # other sessions from the same process that don't have this plugin turned on might.
    #
    # This session will still be able to work with it, as if, when expecting a connection
    # terminated by a different session, it will just retry on a new one and keep it open.
    #
    # This plugin is also not recommendable when connecting to >9000 (like, a lot) different origins.
    # So when you use this, make sure that you don't fall into this trap.
    #
    # https://gitlab.com/os85/httpx/wikis/Persistent
    #
    module Persistent
      class << self
        def load_dependencies(klass)
          klass.plugin(:fiber_concurrency)

          max_retries = if klass.default_options.respond_to?(:max_retries)
            [klass.default_options.max_retries, 1].max
          else
            1
          end
          klass.plugin(:retries, max_retries: max_retries)
        end
      end

      def self.extra_options(options)
        options.merge(persistent: true)
      end

      module InstanceMethods
        def close(*)
          super

          # traverse other threads and unlink respective selector
          # WARNING: this is not thread safe, make sure that the session isn't being
          # used anymore, or all non-main threads are stopped.
          Thread.list.each do |th|
            store = thread_selector_store(th)

            next unless store && store.key?(self)

            selector = store.delete(self)

            selector_close(selector)
          end
        end

        private

        def retryable_request?(request, response, *)
          super || begin
            return false unless response && response.is_a?(ErrorResponse)

            error = response.error

            Retries::RECONNECTABLE_ERRORS.any? { |klass| error.is_a?(klass) }
          end
        end

        def retryable_error?(ex, options)
          super &&
            # under the persistent plugin rules, requests are only retried for connection related errors,
            # which do not include request timeout related errors. This only gets overriden if the end user
            # manually changed +:max_retries+ to something else, which means it is aware of the
            # consequences.
            (!ex.is_a?(RequestTimeoutError) || options.max_retries != 1)
        end
      end
    end
    register_plugin :persistent, Persistent
  end
end
