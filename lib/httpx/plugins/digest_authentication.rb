# frozen_string_literal: true

module HTTPX
  module Plugins
    module DigestAuthentication
      DigestError = Class.new(Error)

      def self.load_dependencies(*)
        require "securerandom"
        require "digest"
      end

      module InstanceMethods
        def digest_authentication(user, password)
          @_digest = Digest.new(user, password)
          self
        end
        alias_method :digest_auth, :digest_authentication

        def request(*args, keep_open: @keep_open, **options)
          return super unless @_digest
          begin
            requests = __build_reqs(*args, **options)
            probe_request = requests.first
            prev_response = __send_reqs(*probe_request).first

            unless prev_response.status == 401
              raise Error, "request doesn't require authentication (status: #{prev_response})"
            end

            probe_request.transition(:idle)
            responses = []

            requests.each do |request|
              token = @_digest.generate_header(request, prev_response)
              request.headers["authorization"] = "Digest #{token}"
              response = __send_reqs(*request).first
              responses << response
              prev_response = response
            end
            return responses.first if responses.size == 1
            responses
          ensure
            close unless keep_open
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
          method = request.verb.to_s.upcase
          www = response.headers["www-authenticate"]

          # TODO: assert if auth-type is Digest
          auth_info = www[/^(\w+) (.*)/, 2]

          uri = request.path

          params = Hash[auth_info.scan(/(\w+)="(.*?)"/)]

          nonce = params["nonce"]
          nc = next_nonce

          # verify qop
          qop = params["qop"]

          if params["algorithm"] =~ /(.*?)(-sess)?$/
            algorithm = case Regexp.last_match(1)
                        when "MD5"    then ::Digest::MD5
                        when "SHA1"   then ::Digest::SHA1
                        when "SHA2"   then ::Digest::SHA2
                        when "SHA256" then ::Digest::SHA256
                        when "SHA384" then ::Digest::SHA384
                        when "SHA512" then ::Digest::SHA512
                        when "RMD160" then ::Digest::RMD160
                        else raise DigestError, "unknown algorithm \"#{Regexp.last_match(1)}\""
            end
            sess = Regexp.last_match(2)
          else
            algorithm = ::Digest::MD5
          end

          if qop || sess
            cnonce = make_cnonce
            nc = format("%08x", nc)
          end

          a1 = if sess
            [algorithm.hexdigest("#{@user}:#{params["realm"]}:#{@password}"),
             nonce,
             cnonce].join ":"
          else
            "#{@user}:#{params["realm"]}:#{@password}"
          end

          ha1 = algorithm.hexdigest(a1)
          ha2 = algorithm.hexdigest("#{method}:#{uri}")
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
