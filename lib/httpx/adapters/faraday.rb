# frozen_string_literal: true

require "delegate"
require "httpx"
require "faraday"

module Faraday
  class Adapter
    class HTTPX < Faraday::Adapter
      def initialize(app = nil, opts = {}, &block)
        @connection = @bind = nil
        super
      end

      module RequestMixin
        def build_connection(env)
          return @connection if @connection

          @connection = ::HTTPX.plugin(:persistent).plugin(ReasonPlugin)
          @connection = @connection.with(@connection_options) unless @connection_options.empty?
          connection_opts = options_from_env(env)

          if (bind = env.request.bind)
            @bind = TCPSocket.new(bind[:host], bind[:port])
            connection_opts[:io] = @bind
          end
          @connection = @connection.with(connection_opts)

          if (proxy = env.request.proxy)
            proxy_options = { uri: proxy.uri }
            proxy_options[:username] = proxy.user if proxy.user
            proxy_options[:password] = proxy.password if proxy.password

            @connection = @connection.plugin(:proxy).with(proxy: proxy_options)
          end
          @connection = @connection.plugin(OnDataPlugin) if env.request.stream_response?

          @connection = @config_block.call(@connection) || @connection if @config_block
          @connection
        end

        def close
          @connection.close if @connection
          @bind.close if @bind
        end

        private

        def connect(env, &blk)
          connection(env, &blk)
        rescue ::HTTPX::TLSError => e
          raise Faraday::SSLError, e
        rescue Errno::ECONNABORTED,
               Errno::ECONNREFUSED,
               Errno::ECONNRESET,
               Errno::EHOSTUNREACH,
               Errno::EINVAL,
               Errno::ENETUNREACH,
               Errno::EPIPE,
               ::HTTPX::ConnectionError => e
          raise Faraday::ConnectionFailed, e
        rescue ::HTTPX::TimeoutError => e
          raise Faraday::TimeoutError, e
        end

        def build_request(env)
          meth = env[:method]

          request_options = {
            headers: env.request_headers,
            body: env.body,
            **options_from_env(env),
          }
          [meth.to_s.upcase, env.url, request_options]
        end

        def options_from_env(env)
          timeout_options = {}
          req_opts = env.request
          if (sec = request_timeout(:read, req_opts))
            timeout_options[:read_timeout] = sec
          end

          if (sec = request_timeout(:write, req_opts))
            timeout_options[:write_timeout] = sec
          end

          if (sec = request_timeout(:open, req_opts))
            timeout_options[:connect_timeout] = sec
          end

          {
            ssl: ssl_options_from_env(env),
            timeout: timeout_options,
          }
        end

        if defined?(::OpenSSL)
          def ssl_options_from_env(env)
            ssl_options = {}

            unless env.ssl.verify.nil?
              ssl_options[:verify_mode] = env.ssl.verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
            end

            ssl_options[:ca_file] = env.ssl.ca_file if env.ssl.ca_file
            ssl_options[:ca_path] = env.ssl.ca_path if env.ssl.ca_path
            ssl_options[:cert_store] = env.ssl.cert_store if env.ssl.cert_store
            ssl_options[:cert] = env.ssl.client_cert if env.ssl.client_cert
            ssl_options[:key] = env.ssl.client_key if env.ssl.client_key
            ssl_options[:ssl_version] = env.ssl.version if env.ssl.version
            ssl_options[:verify_depth] = env.ssl.verify_depth if env.ssl.verify_depth
            ssl_options[:min_version] = env.ssl.min_version if env.ssl.min_version
            ssl_options[:max_version] = env.ssl.max_version if env.ssl.max_version
            ssl_options
          end
        else
          # :nocov:
          def ssl_options_from_env(*)
            {}
          end
          # :nocov:
        end
      end

      include RequestMixin

      module OnDataPlugin
        module RequestMethods
          attr_writer :response_on_data

          def response=(response)
            super

            return unless @response

            return if @response.is_a?(::HTTPX::ErrorResponse)

            @response.body.on_data = @response_on_data
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
            Net::HTTP::STATUS_CODES.fetch(@status, "Non-Standard status code")
          end
        end
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

        def initialize(options)
          @handlers = []
          @connection_options = options
        end

        def enqueue(request)
          handler = ResponseHandler.new(request)
          @handlers << handler
          handler
        end

        def run
          return unless @handlers.last

          env = @handlers.last.env

          connect(env) do |session|
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
              handler.on_complete.call(handler.env) if handler.on_complete
            end
          end
        end

        private

        # from Faraday::Adapter#connection
        def connection(env)
          conn = build_connection(env)
          return conn unless block_given?

          yield conn
        end

        # from Faraday::Adapter#request_timeout
        def request_timeout(type, options)
          key = Faraday::Adapter::TIMEOUT_KEYS[type]
          options[key] || options[:timeout]
        end
      end

      self.supports_parallel = true

      class << self
        def setup_parallel_manager(options = {})
          ParallelManager.new(options)
        end
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

        response = connect_and_request(env)
        save_response(env, response.status, response.body.to_s, response.headers, response.reason) do |response_headers|
          response_headers.merge!(response.headers)
        end
        @app.call(env)
      end

      private

      def connect_and_request(env)
        connect(env) do |session|
          request = session.build_request(*build_request(env))

          request.response_on_data = env.request.on_data if env.request.stream_response?

          response = session.request(request)
          # do not call #raise_for_status for HTTP 4xx or 5xx, as faraday has a middleware for that.
          response.raise_for_status unless response.is_a?(::HTTPX::Response)
          response
        end
      end

      def parallel?(env)
        env[:parallel_manager]
      end
    end

    register_middleware httpx: HTTPX
  end
end
