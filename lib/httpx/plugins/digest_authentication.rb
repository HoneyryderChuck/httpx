# frozen_string_literal: true

require "digest"

module HTTPX
  module Plugins
    #
    # This plugin adds helper methods to implement HTTP Digest Auth (https://tools.ietf.org/html/rfc7616)
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Authentication#authentication
    #
    module DigestAuthentication
      using RegexpExtensions unless Regexp.method_defined?(:match?)

      DigestError = Class.new(Error)

      def self.extra_options(options)
        Class.new(options.class) do
          def_option(:digest, <<-OUT)
            raise Error, ":digest must be a Digest" unless value.is_a?(#{Digest})

            value
          OUT
        end.new(options).merge(max_concurrent_requests: 1)
      end

      def self.load_dependencies(*)
        require "securerandom"
        require "digest"
      end

      module InstanceMethods
        def digest_authentication(user, password)
          with(digest: Digest.new(user, password))
        end

        alias_method :digest_auth, :digest_authentication

        def send_requests(*requests, options)
          requests.flat_map do |request|
            digest = request.options.digest

            if digest
              probe_response = wrap { super(request, options).first }

              if digest && !probe_response.is_a?(ErrorResponse) &&
                 probe_response.status == 401 && probe_response.headers.key?("www-authenticate") &&
                 /Digest .*/.match?(probe_response.headers["www-authenticate"])

                request.transition(:idle)

                token = digest.generate_header(request, probe_response)
                request.headers["authorization"] = "Digest #{token}"

                super(request, options)
              else
                probe_response
              end
            else
              super(request, options)
            end
          end
        end
      end

      class Digest
        def initialize(user, password)
          @user = user
          @password = password
          @nonce = 0
        end

        def generate_header(request, response, _iis = false)
          meth = request.verb.to_s.upcase
          www = response.headers["www-authenticate"]

          # discard first token, it's Digest
          auth_info = www[/^(\w+) (.*)/, 2]

          uri = request.path

          params = Hash[auth_info.split(/ *, */)
                                 .map { |val| val.split("=") }
                                 .map { |k, v| [k, v.delete("\"")] }]
          nonce = params["nonce"]
          nc = next_nonce

          # verify qop
          qop = params["qop"]

          if params["algorithm"] =~ /(.*?)(-sess)?$/
            alg = Regexp.last_match(1)
            algorithm = ::Digest.const_get(alg)
            raise DigestError, "unknown algorithm \"#{alg}\"" unless algorithm

            sess = Regexp.last_match(2)
            params.delete("algorithm")
          else
            algorithm = ::Digest::MD5
          end

          if qop || sess
            cnonce = make_cnonce
            nc = format("%<nonce>08x", nonce: nc)
          end

          a1 = if sess
            [algorithm.hexdigest("#{@user}:#{params["realm"]}:#{@password}"),
             nonce,
             cnonce].join ":"
          else
            "#{@user}:#{params["realm"]}:#{@password}"
          end

          ha1 = algorithm.hexdigest(a1)
          ha2 = algorithm.hexdigest("#{meth}:#{uri}")
          request_digest = [ha1, nonce]
          request_digest.push(nc, cnonce, qop) if qop
          request_digest << ha2
          request_digest = request_digest.join(":")

          header = [
            %(username="#{@user}"),
            %(nonce="#{nonce}"),
            %(uri="#{uri}"),
            %(response="#{algorithm.hexdigest(request_digest)}"),
          ]
          header << %(realm="#{params["realm"]}") if params.key?("realm")
          header << %(algorithm=#{params["algorithm"]}") if params.key?("algorithm")
          header << %(opaque="#{params["opaque"]}") if params.key?("opaque")
          header << %(cnonce="#{cnonce}") if cnonce
          header << %(nc=#{nc})
          header << %(qop=#{qop}) if qop
          header.join ", "
        end

        private

        def make_cnonce
          ::Digest::MD5.hexdigest [
            Time.now.to_i,
            Process.pid,
            SecureRandom.random_number(2**32),
          ].join ":"
        end

        def next_nonce
          @nonce += 1
        end
      end
    end

    register_plugin :digest_authentication, DigestAuthentication
  end
end
