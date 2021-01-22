# frozen_string_literal: true

require "set"

module HTTPX
  module Plugins
    #
    # This plugin adds AWS Sigv4 authentication.
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/AWS-SigV4
    #
    module AWSSigV4
      class Signer
        def initialize(
          username:,
          password:,
          service:,
          region:,
          provider_prefix: "aws",
          unsigned_headers: [],
          apply_checksum_header: true,
          security_token: nil
        )
          @username = username
          @password = password
          @service = service
          @region = region

          @unsigned_headers = Set.new(unsigned_headers.map(&:downcase))
          @unsigned_headers << "authorization"
          @unsigned_headers << "x-amzn-trace-id"
          @unsigned_headers << "expect"
          # TODO: remove it
          @unsigned_headers << "accept"
          @unsigned_headers << "user-agent"
          @unsigned_headers << "content-type"

          @apply_checksum_header = apply_checksum_header
          @provider_prefix = provider_prefix

          @security_token = security_token

          @algorithm = "AWS4-HMAC-SHA256"
        end

        def sign!(request)
          datetime = (request.headers["x-amz-date"] ||= Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
          date = datetime[0, 8]

          content_sha256 = request.headers["x-amz-content-sha256"] || sha256_hexdigest(request.body)

          request.headers["x-amz-content-sha256"] ||= content_sha256 if @apply_checksum_header
          request.headers["x-amz-security-token"] ||= @security_token if @security_token

          signature_headers = request.headers.each.reject do |k, _|
            @unsigned_headers.include?(k)
          end.sort_by(&:first)

          signed_headers = signature_headers.map(&:first).join(";")

          canonical_headers = signature_headers.map do |k, v|
            # eliminate whitespace between value fields, unless it's a quoted value
            "#{k}:#{v.start_with?("\"") && v.end_with?("\"") ? v : v.gsub(/\s+/, " ").strip}\n"
          end.join

          # canonical request
          creq = "#{request.verb.to_s.upcase}" \
            "\n#{request.canonical_path}" \
            "\n#{request.canonical_query}" \
            "\n#{canonical_headers}" \
            "\n#{signed_headers}" \
            "\n#{content_sha256}"

          credential_scope = "#{date}" \
            "/#{@region}" \
            "/#{@service}" \
            "/aws4_request"

          # string to sign
          sts = "#{@algorithm}" \
                "\n#{datetime}" \
                "\n#{credential_scope}" \
                "\n#{sha256_hexdigest(creq)}"

          # signature
          k_date = hmac("AWS4#{@password}", date)
          k_region = hmac(k_date, @region)
          k_service = hmac(k_region, @service)
          k_credentials = hmac(k_service, "aws4_request")
          sig = hexhmac(k_credentials, sts)

          credential = "#{@username}/#{credential_scope}"
          # apply signature
          request.headers["authorization"] =
            "AWS4-HMAC-SHA256 Credential=#{credential}, " \
            "SignedHeaders=#{signed_headers}, " \
            "Signature=#{sig}"
        end

        private

        def sha256_hexdigest(value)
          if value.respond_to?(:to_path)
            # files, pathnames
            OpenSSL::Digest::SHA256.file(value.to_path).hexdigest
          elsif value.respond_to?(:each)
            sha256 = OpenSSL::Digest.new("SHA256")

            mb_buffer = value.each.each_with_object("".b) do |chunk, buffer|
              buffer << chunk
              break if buffer.bytesize >= 1024 * 1024
            end

            sha256.update(mb_buffer)
            value.rewind
            sha256.hexdigest
          else
            OpenSSL::Digest::SHA256.hexdigest(value)
          end
        end

        def hmac(key, value)
          OpenSSL::HMAC.digest(OpenSSL::Digest.new("sha256"), key, value)
        end

        def hexhmac(key, value)
          OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), key, value)
        end
      end

      class << self
        def extra_options(options)
          Class.new(options.class) do
            def_option(:sigv4_signer) do |signer|
              if signer.is_a?(Signer)
                signer
              else
                Signer.new(signer)
              end
            end

            def_option(:sigv4_password)
          end.new.merge(options)
        end

        def load_dependencies(klass)
          require "openssl"
          klass.plugin(:authentication)
        end
      end

      module InstanceMethods
        def aws_sigv4_authentication(**options)
          with(sigv4_signer: Signer.new(**options))
        end

        def build_request(*, _)
          request = super

          return request if request.headers.key?("authorization")

          signer = request.options.sigv4_signer

          return request unless signer

          signer.sign!(request)

          request
        end
      end

      module RequestMethods
        def canonical_path
          path = uri.path.dup
          path << "/" if path.empty?
          path.gsub(%r{[^/]+}) { |part| CGI.escape(part.encode("UTF-8")).gsub("+", "%20").gsub("%7E", "~") }
        end

        def canonical_query
          params = query.split("&")
          # params = params.map { |p| p.match(/=/) ? p : p + '=' }
          # From: https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
          # Sort the parameter names by character code point in ascending order.
          # Parameters with duplicate names should be sorted by value.
          #
          # Default sort <=> in JRuby will swap members
          # occasionally when <=> is 0 (considered still sorted), but this
          # causes our normalized query string to not match the sent querystring.
          # When names match, we then sort by their values.  When values also
          # match then we sort by their original order
          params.each.with_index.sort do |a, b|
            a, a_offset = a
            b, b_offset = b
            a_name, a_value = a.split("=")
            b_name, b_value = b.split("=")
            if a_name == b_name
              if a_value == b_value
                a_offset <=> b_offset
              else
                a_value <=> b_value
              end
            else
              a_name <=> b_name
            end
          end.map(&:first).join("&")
        end
      end
    end
    register_plugin :aws_sigv4, AWSSigV4
  end
end
