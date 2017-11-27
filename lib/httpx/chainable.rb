# frozen_string_literal: true

require "base64"

module HTTPX
  module Chainable
    %i[head get post put delete trace options connect patch].each do |meth|
      define_method meth do |uri, options = {}|
        request meth, uri, options
      end
    end

    # Make an HTTP request with the given verb
    # @param uri
    # @option options [Hash]
    def request(verb, uri, options = {})
      branch(options).request verb, uri
    end

    # @overload timeout(options = {})
    #   Syntax sugar for `timeout(:per_operation, options)`
    # @overload timeout(klass, options = {})
    #   Adds a timeout to the request.
    #   @param [#to_sym] klass
    #     either :null, :global, or :per_operation
    #   @param [Hash] options
    #   @option options [Float] :read Read timeout
    #   @option options [Float] :write Write timeout
    #   @option options [Float] :connect Connect timeout
    def timeout(klass, options = {}) # rubocop:disable Style/OptionHash
      if klass.is_a? Hash
        options = klass
        klass   = :per_operation
      end

      klass = case klass.to_sym
              when :null          then HTTPX::Timeout::Null
              when :global        then HTTPX::Timeout::Global
              when :per_operation then HTTPX::Timeout::PerOperation
              else raise ArgumentError, "Unsupported Timeout class: #{klass}"
              end

      %i[read write connect].each do |k|
        next unless options.key? k
        options["#{k}_timeout".to_sym] = options.delete k
      end

      branch default_options.merge(
        :timeout_class => klass,
        :timeout_options => options
      )
    end

    # @overload persistent(host, timeout: 5)
    #   Flags as persistent
    #   @param  [String] host
    #   @option [Integer] timeout Keep alive timeout
    #   @raise  [Request::Error] if Host is invalid
    #   @return [HTTPX::Client] Persistent client
    # @overload persistent(host, timeout: 5, &block)
    #   Executes given block with persistent client and automatically closes
    #   connection at the end of execution.
    #
    #   @example
    #
    #       def keys(users)
    #         HTTP.persistent("https://github.com") do |http|
    #           users.map { |u| http.get("/#{u}.keys").to_s }
    #         end
    #       end
    #
    #       # same as
    #
    #       def keys(users)
    #         http = HTTP.persistent "https://github.com"
    #         users.map { |u| http.get("/#{u}.keys").to_s }
    #       ensure
    #         http.close if http
    #       end
    #
    #
    #   @yieldparam [HTTPX::Client] client Persistent client
    #   @return [Object] result of last expression in the block
    def persistent(host, timeout: 5)
      options  = {:keep_alive_timeout => timeout}
      p_client = branch default_options.merge(options).with_persistent host
      return p_client unless block_given?
      yield p_client
    ensure
      p_client.close if p_client
    end

    # Make a request through an HTTP proxy
    # @param [Array] proxy
    # @raise [Request::Error] if HTTP proxy is invalid
    def via(*proxy)
      proxy_hash = {}
      proxy_hash[:proxy_address]  = proxy[0] if proxy[0].is_a?(String)
      proxy_hash[:proxy_port]     = proxy[1] if proxy[1].is_a?(Integer)
      proxy_hash[:proxy_username] = proxy[2] if proxy[2].is_a?(String)
      proxy_hash[:proxy_password] = proxy[3] if proxy[3].is_a?(String)
      proxy_hash[:proxy_headers]  = proxy[2] if proxy[2].is_a?(Hash)
      proxy_hash[:proxy_headers]  = proxy[4] if proxy[4].is_a?(Hash)

      raise(RequestError, "invalid HTTP proxy: #{proxy_hash}") unless (2..5).cover?(proxy_hash.keys.size)

      branch default_options.with_proxy(proxy_hash)
    end
    alias through via

    # Make client follow redirects.
    # @param opts
    # @return [HTTPX::Client]
    # @see Redirector#initialize
    def follow(options = {}) # rubocop:disable Style/OptionHash
      branch default_options.with_follow options
    end

    # Make a request with the given headers
    # @param headers
    def headers(headers)
      branch default_options.with_headers(headers)
    end

    # Make a request with the given cookies
    def cookies(cookies)
      branch default_options.with_cookies(cookies)
    end

    # Force a specific encoding for response body
    def encoding(encoding)
      branch default_options.with_encoding(encoding)
    end

    # Accept the given MIME type(s)
    # @param type
    def accept(type)
      headers Headers::ACCEPT => MimeType.normalize(type)
    end

    # Make a request with the given Authorization header
    # @param [#to_s] value Authorization header value
    def auth(value)
      headers Headers::AUTHORIZATION => value.to_s
    end

    # Make a request with the given Basic authorization header
    # @see http://tools.ietf.org/html/rfc2617
    # @param [#fetch] opts
    # @option opts [#to_s] :user
    # @option opts [#to_s] :pass
    def basic_auth(opts)
      user = opts.fetch :user
      pass = opts.fetch :pass

      auth("Basic " + Base64.strict_encode64("#{user}:#{pass}"))
    end

    # Get options for HTTP
    # @return [HTTPX::Options]
    def default_options
      @default_options ||= HTTPX::Options.new
    end

    # Set options for HTTP
    # @param opts
    # @return [HTTPX::Options]
    def default_options=(opts)
      @default_options = HTTPX::Options.new(opts)
    end

    # Set TCP_NODELAY on the socket
    def nodelay
      branch default_options.with_nodelay(true)
    end

    # Turn on given features. Available features are:
    # * auto_inflate
    # * auto_deflate
    # @param features
    def use(*features)
      branch default_options.with_features(features)
    end

    private

    # :nodoc:
    def branch(options)
      HTTPX::Client.new(options)
    end
  end
end

