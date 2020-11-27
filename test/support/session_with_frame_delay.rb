# frozen_string_literal: true

#
# This module is used only to test frame errors for HTTP/2. It targets the settings timeout of
# nghttp2.org, which is known as being 10 seconnds.
#
module SessionWithFrameDelay
  module ConnectionMethods
    def send_pending
      sleep(11)
      super
    end
  end
end
