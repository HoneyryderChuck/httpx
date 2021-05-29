# frozen_string_literal: true

require_relative "test"

class NTLMServer < TestServer
  class NTLMApp < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(req, res) # rubocop:disable Naming/MethodName
      if req["Authorization"] =~ /^NTLM (.*)/
        authorization = Regexp.last_match(1).unpack("m*")[0] # rubocop:disable Style/UnpackFirst

        case authorization
        when /^NTLMSSP\000\001/
          type2 = "TlRMTVNTUAACAAAADAAMADAAAAABAoEAASNFZ4mr" \
            "ze8AAAAAAAAAAGIAYgA8AAAARABPAE0AQQBJAE4A" \
            "AgAMAEQATwBNAEEASQBOAAEADABTAEUAUgBWAEUA" \
            "UgAEABQAZABvAG0AYQBpAG4ALgBjAG8AbQADACIA" \
            "cwBlAHIAdgBlAHIALgBkAG8AbQBhAGkAbgAuAGMA" \
            "bwBtAAAAAAA="

          res["WWW-Authenticate"] = "NTLM #{type2}"
          res.status = 401
        when /^NTLMSSP\000\003/
          res.body = "ok"
        else
          res["WWW-Authenticate"] = "NTLM"
          res.status = 401
        end
      else
        res["WWW-Authenticate"] = "NTLM"
        res.status = 401
      end
    end
  end

  def initialize(options = {})
    super
    mount("/", NTLMApp)
  end
end
