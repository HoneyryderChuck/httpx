# frozen_string_literal: true

module HTTPX
  module Transcoder::Multipart
    module MimeTypeDetector
      module_function

      DEFAULT_MIMETYPE = "application/octet-stream"

      # inspired by https://github.com/shrinerb/shrine/blob/master/lib/shrine/plugins/determine_mime_type.rb
      if defined?(FileMagic)
        MAGIC_NUMBER = 256 * 1024

        def call(file, _)
          return nil if file.eof? # FileMagic returns "application/x-empty" for empty files

          mime = FileMagic.open(FileMagic::MAGIC_MIME_TYPE) do |filemagic|
            filemagic.buffer(file.read(MAGIC_NUMBER))
          end

          file.rewind

          mime
        end
      elsif defined?(Marcel)
        def call(file, filename)
          return nil if file.eof? # marcel returns "application/octet-stream" for empty files

          Marcel::MimeType.for(file, name: filename)
        end

      elsif defined?(MimeMagic)

        def call(file, _)
          mime = MimeMagic.by_magic(file)
          mime.type if mime
        end

      elsif system("which file", out: File::NULL)
        require "open3"

        def call(file, _)
          return if file.eof? # file command returns "application/x-empty" for empty files

          Open3.popen3(*%w[file --mime-type --brief -]) do |stdin, stdout, stderr, thread|
            begin
              IO.copy_stream(file, stdin.binmode)
            rescue Errno::EPIPE
            end
            file.rewind
            stdin.close

            status = thread.value

            # call to file command failed
            if status.nil? || !status.success?
              $stderr.print(stderr.read)
            else

              output = stdout.read.strip

              if output.include?("cannot open")
                $stderr.print(output)
              else
                output
              end
            end
          end
        end

      else

        def call(_, _); end

      end
    end
  end
end
