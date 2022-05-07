# frozen_string_literal: true

require "time"
require "securerandom"
require "digest"

module HTTPX
  module Plugins
    module Authentication
      class Digest
        using RegexpExtensions unless Regexp.method_defined?(:match?)

        def initialize(user, password)
          @user = user
          @password = password
          @nonce = 0
        end

        def can_authenticate?(response)
          !response.is_a?(ErrorResponse) &&
            response.status == 401 && response.headers.key?("www-authenticate") &&
            /Digest .*/.match?(response.headers["www-authenticate"])
        end

        def authenticate(request, response)
          "Digest #{generate_header(request, response)}"
        end

        private

        def generate_header(request, response, iis = false)
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
          if qop
            header << iis ? %(qop="#{qop}") : %(qop=#{qop})
          end
          header.join ", "
        end

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
  end
end
