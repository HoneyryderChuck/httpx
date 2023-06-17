# frozen_string_literal: true

require "delegate"
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

      unless Faraday::RequestOptions.method_defined?(:stream_response?)
        module RequestOptionsExtensions
          refine Faraday::RequestOptions do
            def stream_response?
              false
            end
          end
        end
        using RequestOptionsExtensions
      end

      module RequestMixin
        using ::HTTPX::HashExtensions

        private

        def build_request(env)
          meth = env[:method]

          request_options = {
            headers: env.request_headers,
            body: env.body,
          }
          [meth.to_s.upcase, env.url, request_options]
        end

        def options_from_env(env)
          timeout_options = {
            connect_timeout: env.request.open_timeout,
            operation_timeout: env.request.timeout,
          }.compact

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

      module OnDataPlugin
        module RequestMethods
          attr_writer :response_on_data

          def response=(response)
            super

            return if response.is_a?(::HTTPX::ErrorResponse)

            response.body.on_data = @response_on_data
          end
        end

        module ResponseBodyMethods
          attr_writer :on_data

          def write(chunk)
            return super unless @on_data

            @on_data.call(chunk, chunk.bytesize)
          end
        end
      end

      module ReasonPlugin
        def self.load_dependencies(*)
          require "net/http/status"
        end

        module ResponseMethods
          def reason
            Net::HTTP::STATUS_CODES.fetch(@status)
          end
        end
      end

      def self.session
        @session ||= ::HTTPX.plugin(:compression).plugin(:persistent).plugin(ReasonPlugin)
      end

      class ParallelManager
        class ResponseHandler < SimpleDelegator
          attr_reader :env

          def initialize(env)
            @env = env
            super
          end

          def on_response(&blk)
            if blk
              @on_response = ->(response) do
                blk.call(response)
              end
              self
            else
              @on_response
            end
          end

          def on_complete(&blk)
            if blk
              @on_complete = blk
              self
            else
              @on_complete
            end
          end
        end

        include RequestMixin

        def initialize
          @handlers = []
        end

        def enqueue(request)
          handler = ResponseHandler.new(request)
          @handlers << handler
          handler
        end

        def run
          return unless @handlers.last

          env = @handlers.last.env

          session = HTTPX.session.with(options_from_env(env))
          session = session.plugin(:proxy).with(proxy: { uri: env.request.proxy }) if env.request.proxy
          session = session.plugin(OnDataPlugin) if env.request.stream_response?

          requests = @handlers.map { |handler| session.build_request(*build_request(handler.env)) }

          if env.request.stream_response?
            requests.each do |request|
              request.response_on_data = env.request.on_data
            end
          end

          responses = session.request(*requests)
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

      def initialize(app, options = {})
        super(app)
        @session_options = options
      end

      def call(env)
        super
        if parallel?(env)
          handler = env[:parallel_manager].enqueue(env)
          handler.on_response do |response|
            if response.is_a?(::HTTPX::Response)
              save_response(env, response.status, response.body.to_s, response.headers, response.reason) do |response_headers|
                response_headers.merge!(response.headers)
              end
            else
              env[:error] = response.error
              save_response(env, 0, "", {}, nil)
            end
          end
          return handler
        end

        session = HTTPX.session
        session = session.with(@session_options) unless @session_options.empty?
        session = session.with(options_from_env(env))
        session = session.plugin(:proxy).with(proxy: { uri: env.request.proxy }) if env.request.proxy
        session = session.plugin(OnDataPlugin) if env.request.stream_response?

        request = session.build_request(*build_request(env))

        request.response_on_data = env.request.on_data if env.request.stream_response?

        response = session.request(request)
        # do not call #raise_for_status for HTTP 4xx or 5xx, as faraday has a middleware for that.
        response.raise_for_status unless response.is_a?(::HTTPX::Response)
        save_response(env, response.status, response.body.to_s, response.headers, response.reason) do |response_headers|
          response_headers.merge!(response.headers)
        end
        @app.call(env)
      rescue ::HTTPX::TLSError => e
        raise SSL_ERROR, e
      rescue Errno::ECONNABORTED,
             Errno::ECONNREFUSED,
             Errno::ECONNRESET,
             Errno::EHOSTUNREACH,
             Errno::EINVAL,
             Errno::ENETUNREACH,
             Errno::EPIPE,
             ::HTTPX::ConnectionError => e
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
