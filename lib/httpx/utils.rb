# frozen_string_literal: true

module HTTPX
  module Utils
    using URIExtensions

    TOKEN = %r{[^\s()<>,;:\\"/\[\]?=]+}.freeze
    VALUE = /"(?:\\"|[^"])*"|#{TOKEN}/.freeze
    FILENAME_REGEX = /\s*filename=(#{VALUE})/.freeze
    FILENAME_EXTENSION_REGEX = /\s*filename\*=(#{VALUE})/.freeze

    module_function

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_time(monotonic_timestamp)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - monotonic_timestamp
    end

    # The value of this field can be either an HTTP-date or a number of
    # seconds to delay after the response is received.
    def parse_retry_after(retry_after)
      # first: bet on it being an integer
      Integer(retry_after)
    rescue ArgumentError
      # Then it's a datetime
      time = Time.httpdate(retry_after)
      time - Time.now
    end

    def get_filename(header, _prefix_regex = nil)
      filename = nil
      case header
      when FILENAME_REGEX
        filename = Regexp.last_match(1)
        filename = Regexp.last_match(1) if filename =~ /^"(.*)"$/
      when FILENAME_EXTENSION_REGEX
        filename = Regexp.last_match(1)
        encoding, _, filename = filename.split("'", 3)
      end

      return unless filename

      filename = URI::DEFAULT_PARSER.unescape(filename) if filename.scan(/%.?.?/).all? { |s| /%[0-9a-fA-F]{2}/.match?(s) }

      filename.scrub!

      filename = filename.gsub(/\\(.)/, '\1') unless /\\[^\\"]/.match?(filename)

      filename.force_encoding ::Encoding.find(encoding) if encoding

      filename
    end

    URIParser = URI::RFC2396_Parser.new

    def to_uri(uri)
      return URI(uri) unless uri.is_a?(String) && !uri.ascii_only?

      uri = URI(URIParser.escape(uri))

      non_ascii_hostname = URIParser.unescape(uri.host)

      non_ascii_hostname.force_encoding(Encoding::UTF_8)

      idna_hostname = Punycode.encode_hostname(non_ascii_hostname)

      uri.host = idna_hostname
      uri.non_ascii_hostname = non_ascii_hostname
      uri
    end

    if defined?(Ractor) &&
       # no ractor support for 3.0
       RUBY_VERSION >= "3.1.0"

      def in_ractor?
        Ractor.main != Ractor.current
      end
    else
      def in_ractor?
        false
      end
    end
  end
end
