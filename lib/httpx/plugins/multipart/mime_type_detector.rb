# frozen_string_literal: true

module HTTPX
  module Plugins::Multipart
    module MimeTypeDetector
      module_function

      DEFAULT_MIMETYPE = "application/octet-stream"

      # inspired by https://github.com/shrinerb/shrine/blob/master/lib/shrine/plugins/determine_mime_type.rb
      if defined?(MIME::Types)

        def call(_file, filename)
          mime = MIME::Types.of(filename).first
          mime.content_type if mime
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
              ::IO.copy_stream(file, stdin.binmode)
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
