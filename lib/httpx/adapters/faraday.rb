# frozen_string_literal: true

require "httpx"
require "faraday"

module Faraday
  class Adapter
    class HTTPX < Faraday::Adapter
      module RequestMixin
        private

        def build_request(env)
          meth = env[:method]

          request_options = {
            headers: env.request_headers,
            body: env.body,
          }
          [meth, env.url, request_options]
        end
      end

      include RequestMixin

      class Session < ::HTTPX::Session
        plugin(:compression)
        plugin(:persistent)

        module ReasonPlugin
          if RUBY_VERSION < "2.5"
            def self.load_dependencies(*)
              require "webrick"
            end
          else
            def self.load_dependencies(*)
              require "net/http/status"
            end
          end
          module ResponseMethods
            if RUBY_VERSION < "2.5"
              def reason
                WEBrick::HTTPStatus::StatusMessage.fetch(@status)
              end
            else
              def reason
                Net::HTTP::STATUS_CODES.fetch(@status)
              end
            end
          end
        end
        plugin(ReasonPlugin)
      end

      class ParallelManager
        class ResponseHandler
          attr_reader :env

          def initialize(env)
            @env = env
          end

          def on_response(&blk)
            if block_given?
              @on_response = lambda do |response|
                blk.call(response)
              end
              self
            else
              @on_response
            end
          end

          def on_complete(&blk)
            if block_given?
              @on_complete = blk
              self
            else
              @on_complete
            end
          end

          def respond_to_missing?(meth)
            @env.respond_to?(meth)
          end

          def method_missing(meth, *args, &blk)
            if @env && @env.respond_to?(meth)
              @env.__send__(meth, *args, &blk)
            else
              super
            end
          end
        end

        include RequestMixin

        def initialize
          @session = Session.new
          @handlers = []
        end

        def enqueue(request)
          handler = ResponseHandler.new(request)
          @handlers << handler
          handler
        end

        def run
          requests = @handlers.map { |handler| build_request(handler.env) }
          env = @handlers.last.env

          timeout_options = {
            connect_timeout: env.request.open_timeout,
            operation_timeout: env.request.timeout,
          }.reject { |_, v| v.nil? }

          options = {
            ssl: env.ssl,
            timeout: timeout_options,
          }

          proxy_options = { uri: env.request.proxy }

          session = @session.with(options)
          session = session.plugin(:proxy).with_proxy(proxy_options) if env.request.proxy

          responses = session.request(requests)
          responses.each_with_index do |response, index|
            handler = @handlers[index]
            handler.on_response.call(response)
            handler.on_complete.call(handler.env)
          end
        end
      end

      self.supports_parallel = true

      class << self
        def setup_parallel_manager
          ParallelManager.new
        end
      end

      def initialize(app)
        super(app)
        @session = Session.new
      end

      def call(env)
        if parallel?(env)
          handler = env[:parallel_manager].enqueue(env)
          handler.on_response do |response|
            save_response(env, response.status, response.body, response.headers, response.reason) do |response_headers|
              response_headers.merge!(response.headers)
            end
          end
          return handler
        end

        request_options = build_request(env)

        timeout_options = {
          connect_timeout: env.request.open_timeout,
          operation_timeout: env.request.timeout,
        }.reject { |_, v| v.nil? }

        options = {
          ssl: env.ssl,
          timeout: timeout_options,
        }

        proxy_options = { uri: env.request.proxy }

        session = @session.with(options)
        session = session.plugin(:proxy).with_proxy(proxy_options) if env.request.proxy
        response = session.__send__(*request_options)
        response.raise_for_status unless response.is_a?(::HTTPX::Response)
        save_response(env, response.status, response.body, response.headers, response.reason) do |response_headers|
          response_headers.merge!(response.headers)
        end
        @app.call(env)
      rescue OpenSSL::SSL::SSLError => err
        raise Error::SSLError, err
      rescue Errno::ECONNABORTED,
             Errno::ECONNREFUSED,
             Errno::ECONNRESET,
             Errno::EHOSTUNREACH,
             Errno::EINVAL,
             Errno::ENETUNREACH,
             Errno::EPIPE => err
        raise Error::ConnectionFailed, err
      end

      private

      def parallel?(env)
        env[:parallel_manager]
      end
    end

    register_middleware httpx: HTTPX
  end
end
