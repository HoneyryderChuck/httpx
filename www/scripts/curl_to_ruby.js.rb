require "optparse"
# require "uri"

def parse_options(command, options)
  OptionParser.new do |opts|
    options[:urls] = []
    options[:require] = []
    options[:plugins] = []
    options[:plugin_options] = Hash.new { |hs, k| hs[k] = {} }
    options[:options] = {
      ssl: {},
      timeout: {},
      headers: {},
    }
    # opts.on("--abstract-unix-socket PATH") do |path|# TODO: Connect via abstract Unix domain socket
    # end
    # opts.on("--alt-svc FILE") do |path| # TODO: nable alt-svc with this cache file
    # end
    # opts.on("--anyauth") do #       Pick any authentication method
    # end
    # opts.on("-a", "--append") do #        Append to target file when uploading
    # end
    opts.on("--basic") do #         Use HTTP Basic Authentication
      options[:auth] = :basic_authentication
    end
    opts.on("--cacert FILE") do |path| # CA certificate to verify peer against
      options[:options][:ssl][:ca_file] = "OpenSSL::X509::Certificate.new(File.read(#{path.inspect}))"
    end
    opts.on("--capath DIR") do |path|
      options[:options][:ssl][:ca_path] = path
    end # CA directory to verify peer against
    opts.on("-E", "--cert PASSWORD") do |cert|
      (options[:options][:ssl][:certificate] ||= {})[:cert] = "OpenSSL::X509::Certificate.new(File.read(#{path.inspect}))"
    end # Client certificate file and password
    # opts.on("--cert-status") #   Verify the status of the server certificate
    # opts.on("--cert-type TYPE") # Certificate file type (DER/PEM/ENG)
    opts.on("--ciphers CIPHERLIST") do |ciphers| # SSL ciphers to use
      options[:options][:ssl][:ciphers] = ciphers
    end
    opts.on("--compressed") do
      options[:plugins] << :compression
    end #    Request compressed response
    # opts.on("--compressed-ssh") # Enable SSH compression
    # opts.on("-K, --config FILE") # Read config from a file
    opts.on("--connect-timeout SECS", Integer) do |timeout|
      options[:options][:timeout][:connect_timeout] = timeout
    end # Maximum time allowed for connection
    opts.on("--connect-to HOST1:PORT1:HOST2:PORT2") do |ios| # Connect to host
      options[:options][:io] = ios.split(":").each_slice(2).map{|*a|a.join(":s")}
    end
    opts.on("-C", "--continue-at OFFSET") # Resumed transfer offset
    opts.on("-b", "--cookie DATAORFILENAME") do |cookie|
      options[:options][:headers][:cookie] = cookie
    end # Send cookies from string/file
    # opts.on("-c", "--cookie-jar FILENAME") # TODO: Write cookies to <filename> after operation
    # opts.on("--create-dirs") #   Create necessary local directory hierarchy
    # opts.on("--crlf") #         Convert LF to CRLF in upload
    # opts.on("--crlfile FILE") # Get a CRL list in PEM format from the given file
    opts.on("-d", "--data DATA") do |data|
      options[:verb] ||= :post
      if data.start_with?("@")
        options[:body] = "File.open(#{data[1..-1].inspect})"
      else
        options[:form] ||= []
        k, v = data.split("=")
        v = v.start_with?("@") ? "File.open(#{v[1..-1].inspect})" : v.inspect
        options[:form] << [k, v]
      end
    end #   HTTP POST data
    opts.on("--data-ascii DATA") do |data|
      options[:verb] ||= :post
      if data.start_with?("@")
        options[:body] = "File.open(#{data[1..-1].inspect})"
      else
        options[:form] ||= []
        k, v = data.split("=")
        v = v.start_with?("@") ? "File.open(#{v[1..-1].inspect})" : v.inspect
        options[:form] << [k, v]
      end
    end # HTTP POST ASCII data
    opts.on("--data-binary DATA") do |data|
      options[:verb] ||= :post
      if data.start_with?("@")
        options[:body] = "File.open(#{data[1..-1].inspect})"
      else
        options[:form] ||= []
        k, v = data.split("=")
        v = v.start_with?("@") ? "File.open(#{v[1..-1].inspect})" : v.inspect
        options[:form] << [k, v]
      end
    end # HTTP POST binary data
    opts.on("--data-raw DATA") do |data|
      options[:form] ||= []
      k, v = data.split("=")
      v = v.start_with?("@") ? "File.open(#{v[1..-1].inspect})" : v.inspect
      options[:form] << [k, v]
    end # HTTP POST data, '@' allowed
    opts.on("--data-urlencode DATA") do |data|
      options[:verb] ||= :post
      options[:require] << "cgi"
      options[:body] = "CGI.escape(#{data.inspect})"
    end # HTTP POST data url encoded
    # opts.on("--delegation LEVEL") # GSS-API delegation permission
    opts.on("--digest") do
      options[:auth] = :digest_authentication
    end #        Use HTTP Digest Authentication
    # opts.on("-q", "--disable") #       Disable .curlrc
    # opts.on("--disable-eprt") #  Inhibit using EPRT or LPRT
    # opts.on("--disable-epsv") #  Inhibit using EPSV
    # opts.on("--disallow-username-in-url") # Disallow username in url
    # opts.on("--dns-interface INTERFACE") # Interface to use for DNS requests
    # opts.on("--dns-ipv4-addr ADDRESS") # IPv4 address to use for DNS requests
    # opts.on("--dns-ipv6-addr ADDRESS") # IPv6 address to use for DNS requests
    # opts.on("--dns-servers ADDRESSES") # DNS server addrs to use
    opts.on("--doh-url URL") do |uri|
      options[:options][:resolver_options] = { resolver_class: :https, uri: uri }
    end # Resolve host names over DOH
    # opts.on("-D", "--dump-header FILENAME") # Write the received headers to <filename>
    # opts.on("--egd-file FILE") # EGD socket path for random data
    opts.on("--expect100-timeout SECONDS", Integer) do |secs|
      options[:plugins] << :expect
      options[:plugin_options][:expect][:expect_timeout] = secs
    end # How long to wait for 100-continue
    opts.on("-f", "--fail") #          Fail silently (no output at all) on HTTP errors
    opts.on("--fail-early") do
      options[:raise_for_status] = true
    end #    Fail on first transfer error, do not continue
    # opts.on("--false-start") #   Enable TLS False Start
    opts.on("-F", "--form NAME=CONTENT") do |data|
      data = URI.decode_www_form(data)
      data.each do |_, val|
        if val[0] = "@"
          options[:plugins] << :multipart
          val.replace("File.open(#{val.slice(1..-1).inspect})")
        end
      end

      options[:verb] ||= :post
      options[:form] = data
    end # Specify multipart MIME data
    opts.on("--form-string <NAME=STRING") do |data|
      options[:verb] ||= :post
      options[:form] = URI.decode_www_form(data)
    end # Specify multipart MIME data
    # opts.on("--ftp-account DATA") # Account data string
    # opts.on("--ftp-alternative-to-user <command> String to replace USER [name]
    # opts.on("--ftp-create-dirs Create the remote dirs if not present
    # opts.on("--ftp-method <method> Control CWD usage
    # opts.on("--ftp-pasv      Use PASV/EPSV instead of PORT
    # opts.on("-P, --ftp-port <address> Use PORT instead of PASV
    # opts.on("--ftp-pret      Send PRET before PASV
    # opts.on("--ftp-skip-pasv-ip Skip the IP address for PASV
    # opts.on("--ftp-ssl-ccc   Send CCC after authenticating
    # opts.on("--ftp-ssl-ccc-mode <active/passive> Set CCC mode
    # opts.on("--ftp-ssl-control Require SSL/TLS for FTP login, clear for transfer
    opts.on("-G", "--get") do
      options[:verb] = :get
    end #           Put the post data in the URL and use GET
    # opts.on("-g", "--globoff") #       Disable URL sequences and ranges using {} and []
    # opts.on("--happy-eyeballs-timeout-ms MILLISECONDS") # TODO: How long to wait in milliseconds for IPv6 before trying IPv4
    # opts.on("--haproxy-protocol Send HAProxy PROXY protocol v1 header
    opts.on("-I", "--head") do
      options[:verb] = :head
      options[:options][:debug_level] = 1
    end #          Show document info only
    opts.on("-H", "--header HEADER/@FILE") do |data|
      k, v = data.split("/")
      v = v.start_with?("@") ? "File.open(#{v[1..-1].inspect})" : v.inspect

      options[:options][:headers][k] = v
    end # Pass custom header(s) to server
    # opts.on("-h, --help          This help text
    # opts.on("--hostpubmd5 <md5> Acceptable MD5 hash of the host public key
    # opts.on("--http0.9       Allow HTTP 0.9 responses
    # opts.on("-0, --http1.0       Use HTTP 1.0
    opts.on("--http1.1") do
      options[:options][:ssl][:alpn_protocols] = %w[http/1.1]
    end #       Use HTTP 1.1
    opts.on("--http2") do
      options[:plugins] << :h2c
    end #         Use HTTP 2
    opts.on("--http2-prior-knowledge") do
      options[:options][:fallback_protocol] = "h2"
    end # Use HTTP 2 without HTTP/1.1 Upgrade
    # opts.on("--ignore-content-length") # TODO: Ignore the size of the remote resource
    # opts.on("-i", "--include") #       TODO: Include protocol response headers in the output
    opts.on("-k", "--insecure") do
      options[:options][:ssl][:verify_mode] = "OpenSSL::SSL::VERIFY_NONE"
    end #      Allow insecure server connections when using SSL
    # opts.on("--interface NAME") # Use network INTERFACE (or address)
    opts.on("-4", "--ipv4") do
      options[:options][:ip_families] = "Socket::AF_INET"
    end #          Resolve names to IPv4 addresses
    opts.on("-6", "--ipv6") do
      options[:options][:ip_families] = "Socket::AF_INET6"
    end #          Resolve names to IPv6 addresses
    # opts.on("-j", "--junk-session-cookies") # Ignore session cookies read from file
    opts.on("--keepalive-time SECONDS", Integer) do |timeout|
      options[:options][:timeout][:keepalive_timeout] = timeout
    end # Interval time for keepalive probes
    opts.on("--key KEY") do |key|
      (options[:options][:ssl][:certificate] ||= {})[:key] = OpenSSL::PKey::PKey.new(File.read(key))
    end #     Private key file name
    # opts.on("--key-type TYPE") # Private key file type (DER/PEM/ENG)
    # opts.on("--krb <level>   Enable Kerberos with security <level>
    # opts.on("--libcurl <file> Dump libcurl equivalent code of this command line
    # opts.on("--limit-rate <speed> Limit transfer speed to RATE
    # opts.on("-l, --list-only     List only mode
    # opts.on("--local-port <num/range> Force use of RANGE for local port numbers
    opts.on("-L", "--location") do
      options[:plugins] << :follow_redirects
    end #      Follow redirects
    # opts.on("--location-trusted") # TODO: Like --location, and send auth to other hosts
    # opts.on("--login-options <options> Server login options
    # opts.on("--mail-auth <address> Originator address of the original email
    # opts.on("--mail-from <address> Mail from this address
    # opts.on("--mail-rcpt <address> Mail to this address
    # opts.on("-M, --manual        Display the full manual
    opts.on("--max-filesize BYTES") # Maximum file size to download
    opts.on("--max-redirs NUM", Integer) do |max|
      options[:plugins] << :retries
      options[:plugin_options][:retries][:max_retries] = max
    end # Maximum number of redirects allowed
    # opts.on("-m", "--max-time SECONDS") # TODO: Maximum time allowed for the transfer
    # opts.on("--metalink      Process given URLs as metalink XML file
    opts.on("--negotiate") do
      options[:auth] = :ntlm_authentication
    end #     Use HTTP Negotiate (SPNEGO) authentication
    # opts.on("-n, --netrc         Must read .netrc for user name and password
    # opts.on("--netrc-file <filename> Specify FILE for netrc
    # opts.on("--netrc-optional Use either .netrc or URL
    # opts.on("-:, --next          Make next URL use its separate set of options
    opts.on("--no-alpn") do #       Disable the ALPN TLS extension
      options[:options][:ssl][:alpn_protocols] = []
    end
    # opts.on("-N, --no-buffer     Disable buffering of the output stream
    # opts.on("--no-keepalive") #  TODO: Disable TCP keepalive on the connection
    # opts.on("--no-npn        Disable the NPN TLS extension
    # opts.on("--no-sessionid") # Disable SSL session-ID reusing
    opts.on("--noproxy NOPROXYLIST") # List of hosts which do not use proxy
    opts.on("--ntlm") do
      options[:plugins] << :ntlm_authentication
    end #          Use HTTP NTLM authentication
    # opts.on("--ntlm-wb") #       Use HTTP NTLM authentication with winbind
    opts.on("--oauth2-bearer TOKEN") do |token|
      options[:options][:headers]["authorization"] = "Bearer #{token}"
    end # OAuth 2 Bearer Token
    opts.on("-o", "--output FILE") do |path|
      options[:copy_to] = path
    end # Write to file instead of stdout
    opts.on("--pass PHRASE") do |pass|
      options[:auth] ||= :basic_authentication
      options[:password] = pass
    end# Pass phrase for the private key
    # opts.on("--path-as-is    Do not squash .. sequences in URL path
    # opts.on("--pinnedpubkey <hashes> FILE/HASHES Public key to verify peer against
    opts.on("--post301") #       Do not switch to GET after following a 301
    opts.on("--post302") #       Do not switch to GET after following a 302
    opts.on("--post303") #       Do not switch to GET after following a 303
    # opts.on("--preproxy [protocol://]host[:port] Use this proxy first
    # opts.on("-#, --progress-bar  Display transfer progress as a bar
    # opts.on("--proto <protocols> Enable/disable PROTOCOLS
    # opts.on("--proto-default <protocol> Use PROTOCOL for any URL missing a scheme
    # opts.on("--proto-redir <protocols> Enable/disable PROTOCOLS on redirect
    opts.on("-x", "--proxy [protocol://]host[:port]") do |proxy|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:uri] = proxy
    end # Use this proxy
    # opts.on("--proxy-anyauth Pick any proxy authentication method
    opts.on("--proxy-basic") do
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:authentication] = :basic
    end #   Use Basic authentication on the proxy
    # opts.on("--proxy-cacert <file> CA certificate to verify peer against for proxy
    # opts.on("--proxy-capath <dir> CA directory to verify peer against for proxy
    # opts.on("--proxy-cert <cert[:passwd]> Set client certificate for proxy
    # opts.on("--proxy-cert-type <type> Client certificate type for HTTPS proxy
    # opts.on("--proxy-ciphers <list> SSL ciphers to use for proxy
    # opts.on("--proxy-crlfile <file> Set a CRL list for proxy
    # opts.on("--proxy-digest  Use Digest authentication on the proxy
    opts.on("--proxy-header <header/@file>") do |header|
    end # Pass custom header(s) to proxy
    opts.on("--proxy-insecure") # Do HTTPS proxy connections without verifying the proxy
    opts.on("--proxy-key <key>") # Private key for HTTPS proxy
    opts.on("--proxy-key-type <type>") # Private key file type for proxy
    opts.on("--proxy-negotiate") # Use HTTP Negotiate (SPNEGO) authentication on the proxy
    opts.on("--proxy-ntlm") #    Use NTLM authentication on the proxy
    opts.on("--proxy-pass <phrase>") do |pass|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:password] = pass
    end # Pass phrase for the private key for HTTPS proxy
    # opts.on("--proxy-pinnedpubkey <hashes> FILE/HASHES public key to verify proxy with
    # opts.on("--proxy-service-name <name> SPNEGO proxy service name
    # opts.on("--proxy-ssl-allow-beast Allow security flaw for interop for HTTPS proxy
    # opts.on("--proxy-tls13-ciphers <ciphersuite list> TLS 1.3 proxy cipher suites
    # opts.on("--proxy-tlsauthtype <type> TLS authentication type for HTTPS proxy
    # opts.on("--proxy-tlspassword <string> TLS password for HTTPS proxy
    # opts.on("--proxy-tlsuser <name> TLS username for HTTPS proxy
    # opts.on("--proxy-tlsv1   Use TLSv1 for HTTPS proxy
    opts.on("-U", "--proxy-user <user:password>") do |user|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:username] = user
    end # Proxy user and password
    # opts.on("--proxy1.0 <host[:port]> Use HTTP/1.0 proxy on given port
    # opts.on("-p", "--proxytunnel")   Operate through an HTTP proxy tunnel (using CONNECT)
    # opts.on("--pubkey <key>  SSH Public key file name
    # opts.on("-Q, --quote         Send command(s) to server before transfer
    # opts.on("--random-file <file> File for reading random data from
    opts.on("-r", "--range RANGE") # Retrieve only the bytes within RANGE
    opts.on("--raw") #           Do HTTP "raw"; no transfer decoding
    opts.on("-e", "--referer URL") do |url|
      options[:options][:headers]["referer"] = url
    end # Referrer URL
    # opts.on("-J", "--remote-header-name Use the header-provided filename
    # opts.on("-O, --remote-name   Write output to a file named as the remote file
    # opts.on("--remote-name-all Use the remote file name for all URLs
    # opts.on("-R, --remote-time   Set the remote file's time on the local output
    opts.on("-X", "--request <command>") do |verb|
      options[:verb] = verb.downcase.to_sym
    end # Specify request command to use
    # opts.on("--request-target Specify the target for this request
    opts.on("--resolve <host:port:address[,address]...>") # Resolve the host+port to this address
    opts.on("--retry <num>", Integer) do |num|
      options[:plugins] << :retries
      # options[:options]
    end #   Retry request if transient problems occur
    opts.on("--retry-connrefused") # Retry on connection refused (use with --retry)
    opts.on("--retry-delay <seconds>", Integer) do |delay|
      options[:plugins] << :retries
      options[:plugin_options][:retries][:retry_after] = delay

    end # Wait time between retries
    # opts.on("--retry-max-time <seconds> Retry only within this period
    # opts.on("--sasl-ir       Enable initial response in SASL authentication
    # opts.on("--service-name <name> SPNEGO service name
    # opts.on("-S, --show-error    Show error even when -s is used
    # opts.on("-s, --silent        Silent mode
    opts.on("--socks4 <host[:port]>") do |socks_authority|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:uri] = "socks4://#{socks_authority}"
    end # SOCKS4 proxy on given host + port
    opts.on("--socks4a <host[:port]>") do |socks_authority|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:uri] = "socks4a://#{socks_authority}"
    end # SOCKS4a proxy on given host + port
    opts.on("--socks5 <host[:port]>") do |socks_authority|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:uri] = "socks5://#{socks_authority}"
    end # SOCKS5 proxy on given host + port
    opts.on("--socks5-basic") do |pass|
      options[:plugins] << :proxy
      options[:plugin_options][:proxy][:password] = pass
    end #  Enable username/password auth for SOCKS5 proxies
    # opts.on("--socks5-gssapi Enable GSS-API auth for SOCKS5 proxies
    # opts.on("--socks5-gssapi-nec Compatibility with NEC SOCKS5 server
    # opts.on("--socks5-gssapi-service <name> SOCKS5 proxy service name for GSS-API
    opts.on("--socks5-hostname <host[:port]>") # SOCKS5 proxy, pass host name to proxy
    # opts.on("-Y, --speed-limit <speed> Stop transfers slower than this
    # opts.on("-y, --speed-time <seconds> Trigger 'speed-limit' abort after this time
    # opts.on("--ssl           Try SSL/TLS
    # opts.on("--ssl-allow-beast Allow security flaw to improve interop
    # opts.on("--ssl-no-revoke Disable cert revocation checks (Schannel)
    # opts.on("--ssl-reqd      Require SSL/TLS
    opts.on("-2", "--sslv2") do
      options[:options][:ssl][:min_version] = :SSL2
    end #        Use SSLv2
    opts.on("-3", "--sslv3") do
      options[:options][:ssl][:min_version] = :SSL3
    end #         Use SSLv3
    opts.on("--stderr") #        Where to redirect stderr
    # opts.on("--styled-output Enable styled output for HTTP headers
    # opts.on("--suppress-connect-headers Suppress proxy CONNECT response headers
    # opts.on("--tcp-fastopen  Use TCP Fast Open
    # opts.on("--tcp-nodelay   Use the TCP_NODELAY option
    # opts.on("-t, --telnet-option <opt=val> Set telnet option
    # opts.on("--tftp-blksize <value> Set TFTP BLKSIZE option
    # opts.on("--tftp-no-options Do not send any TFTP options
    # opts.on("-z, --time-cond <time> Transfer based on a time condition
    opts.on("--tls-max <VERSION>") do |version|
      options[:options][:ssl][:max_version] = version.sub("v", "").sub(".", "_").upcase.to_sym
    end # Set maximum allowed TLS version
    # opts.on("--tls13-ciphers <list of TLS 1.3 ciphersuites> TLS 1.3 cipher suites to use
    # opts.on("--tlsauthtype <type> TLS authentication type
    # opts.on("--tlspassword   TLS password
    # opts.on("--tlsuser <name> TLS user name
    opts.on("-1", "--tlsv1") do
      options[:options][:ssl][:min_version] = :TLS1_0
    end #         Use TLSv1.0 or greater
    opts.on("--tlsv1.0") do
      options[:options][:ssl][:min_version] = :TLS1_0
    end #       Use TLSv1.0 or greater
    opts.on("--tlsv1.1") do
      options[:options][:ssl][:min_version] = :TLS1_1
    end #       Use TLSv1.1 or greater
    opts.on("--tlsv1.2") do
      options[:options][:ssl][:min_version] = :TLS1_2
    end #       Use TLSv1.2 or greater
    opts.on("--tlsv1.3") do
      options[:options][:ssl][:min_version] = :TLS1_3
    end #       Use TLSv1.3 or greater
    opts.on("--tr-encoding") #   Request compressed transfer encoding
    # opts.on("--trace <file>  Write a debug trace to FILE
    # opts.on("--trace-ascii <file> Like --trace, but without hex output
    # opts.on("--trace-time    Add time stamps to trace/verbose output
    opts.on("--unix-socket <path>") do |path|
      options[:options][:transport] = :unix
      options[:options][:addresses] = [path]
    end # Connect through this Unix domain socket
    opts.on("-T", "--upload-file <file>") do |path|
      options[:verb] = :put
      options[:body] = Pathname.open(path)
    end # Transfer local FILE to destination
    opts.on("--url <url>") do |url|
      options[:urls] << url
    end #    URL to work with
    opts.on("-B", "--use-ascii") #     Use ASCII/text transfer
    opts.on("-u", "--user <user:password>") do |user_pass|
      options[:auth] ||= :basic_authentication
      user, pass = user_pass.split(":")
      options[:username] = user
      options[:password] = pass
    end # Server user and password
    opts.on("-A", "--user-agent <name>") do |uagent|
      options[:options][:headers]["user-agent"] = uagent
    end # Send User-Agent <name> to server
    opts.on("-v", "--verbose") do
      options[:options][:debug_level] = 2
    end #       Make the operation more talkative
    # opts.on("-V", "--version") #       Show version number and quit
    # opts.on("-w", "--write-out <format> Use output FORMAT after completion
    # opts.on("--xattr         Store metadata in extended file attributes
  end.parse(command)
end

def to_ruby(urls, options)
  template = <<-HTTPX.slice(0..-2)
require "httpx"

http = HTTPX
  HTTPX

  # load extra deps
  options[:require].uniq.each do |lib|
    template.prepend("require \"#{lib}\"\n")
  end

  # load plugins
  options[:plugins].each do |plugin|
    template += ".plugin(#{plugin.inspect}"
    options[:plugin_options][plugin].each do |key, value|
      template += ", #{key}: #{value.inspect}"
    end
    template += ")"
  end

  # handle auth
  if (auth = options[:auth])
    template += ".plugin(#{auth.inspect})." \
                "#{auth}(#{options[:username].inspect}, " \
                "#{options[:password].inspect})"
  end

  # handle general options
  with_options = options[:options].map do |k, v|
    next if %i[body form json].include?(k)

    "#{k}: #{v.inspect}" unless v.respond_to?(:empty?) && v.empty?
  end.compact

  if not with_options.empty?
    template += ".with(#{with_options.join(', ')})"
  end


  # send request
  template += "\nresponse = http"
  template += ".#{options.fetch(:verb, :get)}("
  template += (urls + options[:urls]).map(&:inspect).join(", ")

  # send body
  if options.key?(:body)
    template += ", body: #{options[:body].inspect}"
  end
  if options.key?(:form)
    template += ", form: {"
    template += options[:form].map do |k, v|
      "#{k}: #{v}"
    end.join(", ")
    template += "}"
  end
  template += ")\n"

  template += "response.raise_for_status\n" if options[:raise_for_status]
  template += "puts response.to_s"
  template
end

def to_httpx
  on_txt_change = lambda do |evt|
    command = `#{evt}.target.value`
    unless command.start_with?("curl ")
      `document.getElementById('curl-command-output').style.display = "none"`
      return
    end

    %x{
      var output = document.getElementById('curl-command-output');
      output.classList.remove("error");
    }
    begin
      options = {}
      urls = parse_options(command.slice(5..-1).split(/ +/), options)
      result = to_ruby(urls, options)
    rescue OptionParser::InvalidOption => error
      result = error.message
      result.sub("invalid", "unsupported")
      `output.classList.add("error")`
    end

    `console.log(#{result})`
    %x{
      output.value = #{result};
      output.rows = #{result.lines.size};
      output.style.display = "block";
    }
  end

  %x{
    var input = document.getElementById('curl-command-input');
    input.addEventListener('change', on_txt_change, false);
  }
end
to_httpx

# if $0 == __FILE__
#   command = ARGV.first

#   return unless command.start_with?("curl ")

#   options = {}

#   urls = parse_options(command.slice(5..-1).split(/ +/), options)
#   puts to_ruby(urls, options)
# end