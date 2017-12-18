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
          @_digest_auth_user = user
          @_digest_auth_pass = password
          @_digest = Digest.new
          self
        end
        alias :digest_auth :digest_authentication

        def request(*args, **options)
          return super unless @_digest
          begin
            #keep_open = @keep_open
            #@keep_open = true

            requests = __build_reqs(*args, **options)
            responses = __send_reqs(*requests)

            failed_requests = []
            failed_responses_ids = responses.each_with_index.map do |response, index|
              next unless response.status == 401
              request = requests[index]

              token = @_digest.generate_header(@_digest_auth_user,
                                               @_digest_auth_pass,
                                               request,
                                               response) 

              request.headers["authorization"] = "Digest #{token}"
              request.transition(:idle)

              failed_requests << request

              index
            end.compact

            return responses if failed_requests.empty?

            repeated_responses = __send_reqs(*failed_requests)
            repeated_responses.each_with_index do |rep, index|
              responses[index] = rep
            end
            return responses.first if responses.size == 1 
            responses
          ensure
            #@keep_open = keep_open
          end
        end
      end

      class Digest
        def initialize
          @nonce = 0
        end

        def generate_header(user, password, request, response, iis = false)
          method = request.verb.to_s.upcase
          www = response.headers["www-authenticate"]

          # TODO: assert if auth-type is Digest
          auth_info = www[/^(\w+) (.*)/, 2]


          params = Hash[ auth_info.scan(/(\w+)="(.*?)"/) ]

          nonce = params["nonce"]
          nc = next_nonce
          
          # verify qop
          qop = params["qop"]

          if params["algorithm"] =~ /(.*?)(-sess)?$/
            algorithm = case $1
            when "MD5"    then ::Digest::MD5
            when "SHA1"   then ::Digest::SHA1
            when "SHA2"   then ::Digest::SHA2
            when "SHA256" then ::Digest::SHA256
            when "SHA384" then ::Digest::SHA384
            when "SHA512" then ::Digest::SHA512
            when "RMD160" then ::Digest::RMD160
            else raise DigestError, "unknown algorithm \"#{$1}\""
            end
            sess = $2
          else
            algorithm = ::Digest::MD5
          end
          
          if qop or sess
            cnonce = make_cnonce 
            nc = "%08x" % nc
          end

          a1 = if sess then
            [ algorithm.hexdigest("#{user}:#{params["realm"]}:#{password}"),
              nonce,
              cnonce,
            ].join ":"
          else
            "#{user}:#{params["realm"]}:#{password}"
          end

          ha1 = algorithm.hexdigest(a1)
          ha2 = algorithm.hexdigest("#{method}:#{request.path}")

          request_digest = [ha1, nonce]
          request_digest.push(nc, cnonce, qop) if qop
          request_digest << ha2
          request_digest = request_digest.join(":")

          header = [
            "username=\"#{user}\"",
            "response=\"#{algorithm.hexdigest(request_digest)}\"",
            "uri=\"#{request.path}\"",
            "nonce=\"#{nonce}\""
          ]
          header << "realm=\"#{params["realm"]}\"" if params.key?("realm")
          header << "opaque=\"#{params["opaque"]}\"" if params.key?("opaque")
          header << "algorithm=#{params["algorithm"]}" if params.key?("algorithm")
          header << "cnonce=#{cnonce}" if cnonce
          header << "nc=#{nc}"
          header << "qop=#{qop}" if qop
  #          
  #          if qop.nil? then
  #          elsif iis then
  #            "qop=\"#{qop}\""
  #          else
  #            "qop=#{qop}"
  #          end,
  #          if qop then
  #            [
  #              "nc=#{"%08x" % nonce}",
  #              "cnonce=\"#{cnonce}\"",
  #            ]
  #          end,
  #          if params.key?("opaque") then
  #            "opaque=\"#{params["opaque"]}\""
  #          end
  #        ].compact

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

