# frozen_string_literal: true

require "set"
require "aws-sdk-s3"

module HTTPX
  module Plugins
    #
    # This plugin adds AWS Sigv4 authentication.
    #
    # https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/AWS-SigV4
    #
    module AWSSigV4
      Credentials = Struct.new(:username, :password, :security_token)

      class Signer
        def initialize(
          service:,
          region:,
          credentials: nil,
          username: nil,
          password: nil,
          security_token: nil,
          provider_prefix: "aws",
          header_provider_field: "amz",
          unsigned_headers: [],
          apply_checksum_header: true,
          algorithm: "SHA256"
        )
          @credentials = credentials || Credentials.new(username, password, security_token)
          @service = service
          @region = region

          @unsigned_headers = Set.new(unsigned_headers.map(&:downcase))
          @unsigned_headers << "authorization"
          @unsigned_headers << "x-amzn-trace-id"
          @unsigned_headers << "expect"

          @apply_checksum_header = apply_checksum_header
          @provider_prefix = provider_prefix
          @header_provider_field = header_provider_field

          @algorithm = algorithm
        end

        def sign!(request)
          lower_provider_prefix = "#{@provider_prefix}4"
          upper_provider_prefix = lower_provider_prefix.upcase

          downcased_algorithm = @algorithm.downcase

          datetime = (request.headers["x-#{@header_provider_field}-date"] ||= Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
          date = datetime[0, 8]

          content_hashed = request.headers["x-#{@header_provider_field}-content-#{downcased_algorithm}"] || hexdigest(request.body)

          request.headers["x-#{@header_provider_field}-content-#{downcased_algorithm}"] ||= content_hashed if @apply_checksum_header
          request.headers["x-#{@header_provider_field}-security-token"] ||= @credentials.security_token if @credentials.security_token

          signature_headers = request.headers.each.reject do |k, _|
            @unsigned_headers.include?(k)
          end
          # aws sigv4 needs to declare the host, regardless of protocol version
          signature_headers << ["host", request.authority] unless request.headers.key?("host")
          signature_headers.sort_by!(&:first)

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
                 "\n#{content_hashed}"

          credential_scope = "#{date}" \
                             "/#{@region}" \
                             "/#{@service}" \
                             "/#{lower_provider_prefix}_request"

          algo_line = "#{upper_provider_prefix}-HMAC-#{@algorithm}"
          # string to sign
          sts = "#{algo_line}" \
                "\n#{datetime}" \
                "\n#{credential_scope}" \
                "\n#{hexdigest(creq)}"

          # signature
          k_date = hmac("#{upper_provider_prefix}#{@credentials.password}", date)
          k_region = hmac(k_date, @region)
          k_service = hmac(k_region, @service)
          k_credentials = hmac(k_service, "#{lower_provider_prefix}_request")
          sig = hexhmac(k_credentials, sts)

          credential = "#{@credentials.username}/#{credential_scope}"
          # apply signature
          request.headers["authorization"] =
            "#{algo_line} " \
            "Credential=#{credential}, " \
            "SignedHeaders=#{signed_headers}, " \
            "Signature=#{sig}"
        end

        private

        def hexdigest(value)
          if value.respond_to?(:to_path)
            # files, pathnames
            OpenSSL::Digest.new(@algorithm).file(value.to_path).hexdigest
          elsif value.respond_to?(:each)
            digest = OpenSSL::Digest.new(@algorithm)

            mb_buffer = value.each.each_with_object("".b) do |chunk, buffer|
              buffer << chunk
              break if buffer.bytesize >= 1024 * 1024
            end

            digest.update(mb_buffer)
            value.rewind
            digest.hexdigest
          else
            OpenSSL::Digest.new(@algorithm).hexdigest(value)
          end
        end

        def hmac(key, value)
          OpenSSL::HMAC.digest(OpenSSL::Digest.new(@algorithm), key, value)
        end

        def hexhmac(key, value)
          OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(@algorithm), key, value)
        end
      end

      class << self
        def load_dependencies(*)
          require "digest/sha2"
          require "openssl"
        end

        def configure(klass)
          klass.plugin(:expect)
          klass.plugin(:compression)
        end
      end

      module OptionsMethods
        def option_sigv4_signer(value)
          value.is_a?(Signer) ? value : Signer.new(value)
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
