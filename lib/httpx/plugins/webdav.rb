# frozen_string_literal: true

module HTTPX
  module Plugins
    #
    # This plugin implements convenience methods for performing WEBDAV requests.
    #
    # https://gitlab.com/os85/httpx/wikis/WebDav
    #
    module WebDav
      def self.configure(klass)
        klass.plugin(:xml)
      end

      module InstanceMethods
        # sends a COPY WebDav request for +src+ and +dest+.
        def copy(src, dest)
          request("COPY", src, headers: { "destination" => @options.origin.merge(dest) })
        end

        # sends a MOVE WebDav request for +src+ and +dest+.
        def move(src, dest)
          request("MOVE", src, headers: { "destination" => @options.origin.merge(dest) })
        end

        # sends a LOCK WebDav request for +path+ (for the time set by +timeout+, when passed).
        # it calls #unlock after the block is executed.
        def lock(path, timeout: nil, &blk)
          headers = {}
          headers["timeout"] = if timeout && timeout.positive?
            "Second-#{timeout}"
          else
            "Infinite, Second-4100000000"
          end
          xml = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>" \
                "<D:lockinfo xmlns:D=\"DAV:\">" \
                "<D:lockscope><D:exclusive/></D:lockscope>" \
                "<D:locktype><D:write/></D:locktype>" \
                "<D:owner>null</D:owner>" \
                "</D:lockinfo>"
          response = request("LOCK", path, headers: headers, xml: xml)

          return response unless response.is_a?(Response)

          return response unless blk && response.status == 200

          lock_token = response.headers["lock-token"]

          begin
            blk.call(response)
          ensure
            unlock(path, lock_token)
          end

          response
        end

        # sends a UNLOCK WebDav request for +path+, using the given +lock_token+.
        def unlock(path, lock_token)
          request("UNLOCK", path, headers: { "lock-token" => lock_token })
        end

        # sends a MKCOL WebDav request for +dir+.
        def mkcol(dir)
          request("MKCOL", dir)
        end

        # sends a PROPFIND WebDav request for +path+.
        def propfind(path, xml = nil)
          body = case xml
                 when :acl
                   '<?xml version="1.0" encoding="utf-8" ?><D:propfind xmlns:D="DAV:"><D:prop><D:owner/>' \
                   "<D:supported-privilege-set/><D:current-user-privilege-set/><D:acl/></D:prop></D:propfind>"
                 when nil
                   '<?xml version="1.0" encoding="utf-8"?><DAV:propfind xmlns:DAV="DAV:"><DAV:allprop/></DAV:propfind>'
                 else
                   xml
          end

          request("PROPFIND", path, headers: { "depth" => "1" }, xml: body)
        end

        # sends a PROPPATCH WebDav request for +path+.
        def proppatch(path, xml)
          body = "<?xml version=\"1.0\"?>" \
                 "<D:propertyupdate xmlns:D=\"DAV:\" xmlns:Z=\"http://ns.example.com/standards/z39.50/\">#{xml}</D:propertyupdate>"
          request("PROPPATCH", path, xml: body)
        end
        # %i[ orderpatch acl report search]
      end
    end
    register_plugin(:webdav, WebDav)
  end
end
