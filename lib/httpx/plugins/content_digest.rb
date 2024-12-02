# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds `Content-Digest` headers to requests
    # and can validate these headers on responses
    #
    # https://datatracker.ietf.org/doc/html/rfc9530
    #
    module ContentDigest
      class Error < HTTPX::Error; end

      # Error raised on response "content-digest" header validation.
      class ValidationError < Error
        attr_reader :response

        def initialize(message, response)
          super(message)
          @response = response
        end
      end

      class MissingContentDigestError < ValidationError; end
      class InvalidContentDigestError < ValidationError; end

      SUPPORTED_ALGORITHMS = {
        "sha-256" => OpenSSL::Digest::SHA256,
        "sha-512" => OpenSSL::Digest::SHA512,
      }.freeze

      class << self
        def extra_options(options)
          options.merge(encode_content_digest: true, validate_content_digest: true, content_digest_algorithm: "sha-256")
        end
      end

      # add support for the following options:
      #
      # :content_digest_algorithm :: the digest algorithm to use. Currently supports `sha-256` and `sha-512`. (defaults to `sha-256`)
      # :encode_content_digest :: whether a <tt>Content-Digest</tt> header should be computed for the request;
      #                           can also be a callable object (i.e. <tt>->(req) { ... }</tt>, defaults to <tt>true</tt>)
      # :validate_content_digest :: whether a <tt>Content-Digest</tt> header in the response should be validated;
      #                             can also be a callable object (i.e. <tt>->(res) { ... }</tt>, defaults to <tt>true</tt>)
      module OptionsMethods
        def option_content_digest_algorithm(value)
          raise TypeError, ":content_digest_algorithm must be one of 'sha-256', 'sha-512'" unless SUPPORTED_ALGORITHMS.key?(value)

          value
        end

        def option_encode_content_digest(value)
          value
        end

        def option_validate_content_digest(value)
          value
        end
      end

      module ResponseBodyMethods
        attr_reader :content_digest_buffer

        def initialize(response, options)
          super

          return unless response.headers.key?("content-digest")

          should_validate = options.validate_content_digest
          should_validate = should_validate.call(response) if should_validate.respond_to?(:call)

          return unless should_validate

          @content_digest_buffer = Response::Buffer.new(
            threshold_size: @options.body_threshold_size,
            bytesize: @length,
            encoding: @encoding
          )
        end

        def write(chunk)
          @content_digest_buffer.write(chunk) if @content_digest_buffer
          super
        end

        def close
          if @content_digest_buffer
            @content_digest_buffer.close
            @content_digest_buffer = nil
          end
          super
        end
      end

      module InstanceMethods
        def build_request(*)
          request = super

          return request if request.headers.key?("content-digest")

          perform_encoding = @options.encode_content_digest
          perform_encoding = perform_encoding.call(request) if perform_encoding.respond_to?(:call)

          return request unless perform_encoding

          digest = base64digest(request.body)
          request.headers.add("content-digest", "#{@options.content_digest_algorithm}=:#{digest}:")

          request
        end

        private

        def fetch_response(request, _, _)
          response = super
          return response unless response.is_a?(Response)

          perform_validation = @options.validate_content_digest
          perform_validation = perform_validation.call(response) if perform_validation.respond_to?(:call)

          validate_content_digest(response) if perform_validation

          response
        rescue ValidationError => e
          ErrorResponse.new(request, e)
        end

        def validate_content_digest(response)
          content_digest_header = response.headers["content-digest"]

          raise MissingContentDigestError.new("response is missing a `content-digest` header", response) unless content_digest_header

          digests = extract_content_digests(content_digest_header)

          included_algorithms = SUPPORTED_ALGORITHMS.keys & digests.keys

          raise MissingContentDigestError.new("unsupported algorithms: #{digests.keys.join(", ")}", response) if included_algorithms.empty?

          content_buffer = response.body.content_digest_buffer

          included_algorithms.each do |algorithm|
            digest = SUPPORTED_ALGORITHMS.fetch(algorithm).new
            digest_received = digests[algorithm]
            digest_computed =
              if content_buffer.respond_to?(:to_path)
                content_buffer.flush
                digest.file(content_buffer.to_path).base64digest
              else
                digest.base64digest(content_buffer.to_s)
              end

            raise InvalidContentDigestError.new("#{algorithm} digest does not match content",
                                                response) unless digest_received == digest_computed
          end
        end

        def extract_content_digests(header)
          header.split(",").to_h do |entry|
            algorithm, digest = entry.split("=", 2)
            raise Error, "#{entry} is an invalid digest format" unless algorithm && digest

            [algorithm, digest.byteslice(1..-2)]
          end
        end

        def base64digest(body)
          digest = SUPPORTED_ALGORITHMS.fetch(@options.content_digest_algorithm).new

          if body.respond_to?(:read)
            if body.respond_to?(:to_path)
              digest.file(body.to_path).base64digest
            else
              raise ContentDigestError, "request body must be rewindable" unless body.respond_to?(:rewind)

              buffer = Tempfile.new("httpx", encoding: Encoding::BINARY, mode: File::RDWR)
              begin
                IO.copy_stream(body, buffer)
                buffer.flush

                digest.file(buffer.to_path).base64digest
              ensure
                body.rewind
                buffer.close
                buffer.unlink
              end
            end
          else
            raise ContentDigestError, "base64digest for endless enumerators is not supported" if body.unbounded_body?

            buffer = "".b
            body.each { |chunk| buffer << chunk }

            digest.base64digest(buffer)
          end
        end
      end
    end
    register_plugin :content_digest, ContentDigest
  end
end
