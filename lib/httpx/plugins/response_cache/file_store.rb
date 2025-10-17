# frozen_string_literal: true

require "pathname"

module HTTPX::Plugins
  module ResponseCache
    # Implementation of a file system based cache store.
    #
    # It stores cached responses in a file under a directory pointed by the +dir+
    # variable (defaults to the default temp directory from the OS), in a custom
    # format (similar but different from HTTP/1.1 request/response framing).
    class FileStore
      CRLF = HTTPX::Connection::HTTP1::CRLF

      attr_reader :dir

      def initialize(dir = Dir.tmpdir)
        @dir = Pathname.new(dir).join("httpx-response-cache")

        FileUtils.mkdir_p(@dir)
      end

      def clear
        FileUtils.rm_rf(@dir)
      end

      def get(request)
        path = file_path(request)

        return unless File.exist?(path)

        File.open(path, mode: File::RDONLY | File::BINARY) do |f|
          f.flock(File::Constants::LOCK_SH)

          read_from_file(request, f)
        end
      end

      def set(request, response)
        path = file_path(request)

        file_exists = File.exist?(path)

        mode = file_exists ? File::RDWR : File::CREAT | File::Constants::WRONLY

        File.open(path, mode: mode | File::BINARY) do |f|
          f.flock(File::Constants::LOCK_EX)

          if file_exists
            cached_response = read_from_file(request, f)

            if cached_response
              next if cached_response == request.cached_response

              cached_response.close

              f.truncate(0)

              f.rewind
            end
          end
          # cache the request headers
          f << request.verb << CRLF
          f << request.uri << CRLF

          request.headers.each do |field, value|
            f << field << ":" << value << CRLF
          end

          f << CRLF

          # cache the response
          f << response.status << CRLF
          f << response.version << CRLF

          response.headers.each do |field, value|
            f << field << ":" << value << CRLF
          end

          f << CRLF

          response.body.rewind

          IO.copy_stream(response.body, f)
        end
      end

      private

      def file_path(request)
        @dir.join(request.response_cache_key)
      end

      def read_from_file(request, f)
        # if it's an empty file
        return if f.eof?

        # read request data
        verb = f.readline.delete_suffix!(CRLF)
        uri = f.readline.delete_suffix!(CRLF)

        request_headers = {}
        while (line = f.readline) != CRLF
          line.delete_suffix!(CRLF)
          sep_index = line.index(":")

          field = line.byteslice(0..(sep_index - 1))
          value = line.byteslice((sep_index + 1)..-1)

          request_headers[field] = value
        end

        status = f.readline.delete_suffix!(CRLF)
        version = f.readline.delete_suffix!(CRLF)

        response_headers = {}
        while (line = f.readline) != CRLF
          line.delete_suffix!(CRLF)
          sep_index = line.index(":")

          field = line.byteslice(0..(sep_index - 1))
          value = line.byteslice((sep_index + 1)..-1)

          response_headers[field] = value
        end

        original_request = request.options.request_class.new(verb, uri, request.options)
        original_request.merge_headers(request_headers)

        response = request.options.response_class.new(request, status, version, response_headers)
        response.original_request = original_request
        response.finish!

        # the cached body is already inflated, so temporarily remove the inflaters
        inflaters = response.body.instance_variable_get(:@inflaters)
        response.body.instance_variable_set(:@inflaters, [])

        begin
          IO.copy_stream(f, response.body)
        ensure
          # add the inflaters back after copying the file to the response body
          response.body.instance_variable_set(:@inflaters, inflaters)
        end

        response
      end
    end
  end
end
