# frozen_string_literal: true

require "time"
require "securerandom"
require "digest"

module HTTPX
  module Plugins
    module Authentication
      class Digest
        class Error < Error
        end

        def initialize(user, password, hashed: false, **)
          @user = user
          @password = password
          @nonce = 0
          @hashed = hashed
        end

        def can_authenticate?(authenticate)
          authenticate && /Digest .*/.match?(authenticate)
        end

        def authenticate(request, authenticate)
          "Digest #{generate_header(request.verb, request.path, authenticate)}"
        end

        private

        def generate_header(meth, uri, authenticate)
          # discard first token, it's Digest
          auth_info = authenticate[/^(\w+) (.*)/, 2]

          raise_format_error unless auth_info

          s = StringScanner.new(auth_info)

          params = {}
          until s.eos?
            k = s.scan_until(/=/)
            raise_format_error unless k&.end_with?("=")

            if s.peek(1) == "\""
              s.skip("\"")
              v = s.scan_until(/"/)
              raise_format_error unless v&.end_with?("\"")

              v = v[0..-2]
              s.skip_until(/,/)
            else
              v = s.scan_until(/,|$/)

              if v&.end_with?(",")
                v = v[0..-2]
              else
                raise_format_error unless s.eos?
              end

              v = v[0..-2] if v&.end_with?(",")
            end
            params[k[0..-2]] = v
            s.skip(/\s/)
          end

          nonce = params["nonce"]
          nc = next_nonce

          # verify qop
          qop = params["qop"]

          if qop
            # some servers send multiple values wrapped in parentheses (i.e. "(qauth,)")
            qop = qop[/\(?([^)]+)\)?/, 1]
            qop = qop.split(",").map { |s| s.delete_prefix("'").delete_suffix("'") }.delete_if(&:empty?).map.first
          end

          if params["algorithm"] =~ /(.*?)(-sess)?$/
            alg = Regexp.last_match(1)
            algorithm = ::Digest.const_get(alg)
            raise Error, "unknown algorithm \"#{alg}\"" unless algorithm

            sess = Regexp.last_match(2)
          else
            algorithm = ::Digest::MD5
          end

          if qop || sess
            cnonce = make_cnonce
            nc = format("%<nonce>08x", nonce: nc)
          end

          a1 = if sess
            [
              (@hashed ? @password : algorithm.hexdigest("#{@user}:#{params["realm"]}:#{@password}")),
              nonce,
              cnonce,
            ].join ":"
          else
            @hashed ? @password : "#{@user}:#{params["realm"]}:#{@password}"
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
          header << %(algorithm=#{params["algorithm"]}) if params.key?("algorithm")
          header << %(cnonce="#{cnonce}") if cnonce
          header << %(nc=#{nc})
          header << %(qop=#{qop}) if qop
          header << %(opaque="#{params["opaque"]}") if params.key?("opaque")
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

        def raise_format_error
          raise Error, "unsupported digest header format"
        end
      end
    end
  end
end
