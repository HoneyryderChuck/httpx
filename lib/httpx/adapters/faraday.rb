# frozen_string_literal: true

require "httpx"
require "faraday"

module Faraday
  class Adapter
    class HTTPX < Faraday::Adapter
      # :nocov:
      SSL_ERROR = if defined?(Faraday::SSLError)
        Faraday::SSLError
      else
        Faraday::Error::SSLError
      end

      CONNECTION_FAILED_ERROR = if defined?(Faraday::ConnectionFailed)
        Faraday::ConnectionFailed
      else
        Faraday::Error::ConnectionFailed
      end
      # :nocov:

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

        def options_from_env(env)
          timeout_options = {
            connect_timeout: env.request.open_timeout,
            operation_timeout: env.request.timeout,
          }.reject { |_, v| v.nil? }

          options = {
            ssl: {},
            timeout: timeout_options,
          }

          options[:ssl][:verify_mode] = OpenSSL::SSL::VERIFY_PEER if env.ssl.verify
          options[:ssl][:ca_file] = env.ssl.ca_file if env.ssl.ca_file
          options[:ssl][:ca_path] = env.ssl.ca_path if env.ssl.ca_path
          options[:ssl][:cert_store] = env.ssl.cert_store if env.ssl.cert_store
          options[:ssl][:cert] = env.ssl.client_cert if env.ssl.client_cert
          options[:ssl][:key] = env.ssl.client_key if env.ssl.client_key
          options[:ssl][:ssl_version] = env.ssl.version if env.ssl.version
          options[:ssl][:verify_depth] = env.ssl.verify_depth if env.ssl.verify_depth
          options[:ssl][:min_version] = env.ssl.min_version if env.ssl.min_version
          options[:ssl][:max_version] = env.ssl.max_version if env.ssl.max_version

          options
        end
      end

      include RequestMixin

      class Session < ::HTTPX::Session
        plugin(:compression)
        plugin(:persistent)

        # :nocov:
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
        # :nocov:
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
            @env.respond_to?(meth) || super
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

          proxy_options = { uri: env.request.proxy }

          session = @session.with(options_from_env(env))
          session = session.plugin(:proxy).with(proxy: proxy_options) if env.request.proxy

          responses = session.request(requests)
          Array(responses).each_with_index do |response, index|
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
        super
        if parallel?(env)
          handler = env[:parallel_manager].enqueue(env)
          handler.on_response do |response|
            save_response(env, response.status, response.body.to_s, response.headers, response.reason) do |response_headers|
              response_headers.merge!(response.headers)
            end
          end
          return handler
        end

        meth, uri, request_options = build_request(env)

        session = @session.with(options_from_env(env))
        session = session.plugin(:proxy).with(proxy: proxy_options) if env.request.proxy
        response = session.__send__(meth, uri, **request_options)
        response.raise_for_status unless response.is_a?(::HTTPX::Response)
        save_response(env, response.status, response.body.to_s, response.headers, response.reason) do |response_headers|
          response_headers.merge!(response.headers)
        end
        @app.call(env)
      rescue OpenSSL::SSL::SSLError => e
        raise SSL_ERROR, e
      rescue Errno::ECONNABORTED,
             Errno::ECONNREFUSED,
             Errno::ECONNRESET,
             Errno::EHOSTUNREACH,
             Errno::EINVAL,
             Errno::ENETUNREACH,
             Errno::EPIPE => e
        raise CONNECTION_FAILED_ERROR, e
      end

      private

      def parallel?(env)
        env[:parallel_manager]
      end
    end

    register_middleware httpx: HTTPX
  end
end
