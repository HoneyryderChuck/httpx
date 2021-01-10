# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin adds support for passing `http-form_data` objects (like file objects) as "multipart/form-data";
    #
    #   HTTPX.post(URL, form: form: { image: HTTP::FormData::File.new("path/to/file")})
    #
    # https://gitlab.com/honeyryderchuck/httpx/wikis/Multipart-Uploads
    #
    module Multipart
      MULTIPART_VALUE_COND = lambda do |value|
        value.respond_to?(:read) ||
          (value.respond_to?(:to_hash) &&
            value.key?(:body) &&
            (value.key?(:filename) || value.key?(:content_type)))
      end

      def self.normalize_keys(key, value, &block)
        Transcoder.normalize_keys(key, value, MULTIPART_VALUE_COND, &block)
      end

      class Part
        attr_reader :value

        def initialize(key, value)
          @key = key

          @value = case value
                   when Hash
                     @content_type = value[:content_type]
                     @filename = value[:filename]
                     value[:body]
                   else
                     value
          end

          case @value
          when Pathname
            @value = @value.open(:binmode => true)
            extract_from_file(@value)
          when File
            extract_from_file(@value)
          when String
            @value = StringIO.new(@value)
          else
            @filename ||= @value.filename if @value.respond_to?(:filename)
            @content_type ||= @value.content_type if @value.respond_to?(:content_type)
            raise Error, "#{@value} does not respond to #read#" unless @value.respond_to?(:read)

            value
          end
        end

        def header
          header = "Content-Disposition: form-data; name=#{@key}".b
          header << "; filename=#{@filename}" if @filename
          header << "\r\n"
          header << "Content-Type: #{@content_type}\r\n" if @content_type
          header << "\r\n"
          header
        end

        private

        def extract_from_file(file)
          @filename ||= File.basename(file.path)
          @content_type ||= determine_mime_type(file) # rubocop:disable Naming/MemoizedInstanceVariableName
        end

        DEFAULT_MIMETYPE = "application/octet-stream"

        # inspired by https://github.com/shrinerb/shrine/blob/master/lib/shrine/plugins/determine_mime_type.rb
        if defined?(MIME::Types)

          def determine_mime_type(_file)
            mime = MIME::Types.of(@filename).first

            return DEFAULT_MIMETYPE unless mime

            mime.content_type
          end

        elsif defined?(MimeMagic)

          def determine_mime_type(file)
            mime = MimeMagic.by_magic(file)

            return DEFAULT_MIMETYPE unless mime

            return mime.type if mime
          end

        elsif system("which file", out: File::NULL)
          require "open3"

          def determine_mime_type(file)
            return if file.eof? # file command returns "application/x-empty" for empty files

            Open3.popen3(*%w[file --mime-type --brief -]) do |stdin, stdout, stderr, thread|
              begin
                ::IO.copy_stream(file, stdin.binmode)
              rescue Errno::EPIPE
              end
              file.rewind
              stdin.close

              status = thread.value

              # call to file command failed
              if status.nil? || !status.success?
                $stderr.print(stderr.read)
                return DEFAULT_MIMETYPE
              end

              output = stdout.read.strip

              if output.include?("cannot open")
                $stderr.print(output)
                return DEFAULT_MIMETYPE
              end

              output
            end
          end

        else

          def determine_mime_type(_file)
            DEFAULT_MIMETYPE
          end

        end
      end

      class MultipartEncoder
        def initialize(form)
          @boundary = ("-" * 21) << SecureRandom.hex(21)
          @part_index = 0
          @buffer = "".b

          @parts = to_parts(form)
        end

        def content_type
          "multipart/form-data; boundary=#{@boundary}"
        end

        def bytesize
          @parts.map(&:size).sum
        end

        def read(length = nil, outbuf = nil)
          data   = outbuf.clear.force_encoding(Encoding::BINARY) if outbuf
          data ||= "".b

          read_chunks(data, length)

          data unless length && data.empty?
        end

        private

        def to_parts(form)
          params = form.each_with_object([]) do |(key, val), aux|
            Multipart.normalize_keys(key, val) do |k, v|
              part = Part.new(k, v)
              aux << StringIO.new("--#{@boundary}\r\n")
              aux << StringIO.new(part.header)
              aux << part.value
              aux << StringIO.new("\r\n")
            end
          end
          params << StringIO.new("--#{@boundary}--\r\n")
          params
        end

        def read_chunks(buffer, length = nil)
          while (chunk = read_from_part(length))
            buffer << chunk.force_encoding(Encoding::BINARY)

            next unless length

            length -= chunk.bytesize

            break if length.zero?
          end
        end

        # if there's a current part to read from, tries to read a chunk.
        def read_from_part(max_length = nil)
          return unless @part_index < @parts.size

          chunk = @parts[@part_index].read(max_length, @buffer)

          return chunk if chunk && !chunk.empty?

          @part_index += 1

          nil
        end
      end

      module FormTranscoder
        module_function

        def encode(form)
          if multipart?(form)
            MultipartEncoder.new(form)
          else
            Transcoder::Form::Encoder.new(form)
          end
        end

        def multipart?(data)
          data.any? do |_, v|
            MULTIPART_VALUE_COND.call(v) ||
              (v.respond_to?(:to_ary) && v.to_ary.any?(&MULTIPART_VALUE_COND)) ||
              (v.respond_to?(:to_hash) && v.to_hash.any? { |_, e| MULTIPART_VALUE_COND.call(e) })
          end
        end
      end

      def self.configure(*)
        Transcoder.register("form", FormTranscoder)
      end
    end
    register_plugin :multipart, Multipart
  end
end
