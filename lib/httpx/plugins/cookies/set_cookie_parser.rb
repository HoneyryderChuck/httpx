# frozen_string_literal: true

require "strscan"
require "time"

module HTTPX
  module Plugins::Cookies
    module SetCookieParser
      using(RegexpExtensions) unless Regexp.method_defined?(:match?)

      # Whitespace.
      RE_WSP = /[ \t]+/.freeze

      # A pattern that matches a cookie name or attribute name which may
      # be empty, capturing trailing whitespace.
      RE_NAME = /(?!#{RE_WSP})[^,;\\"=]*/.freeze

      RE_BAD_CHAR = /([\x00-\x20\x7F",;\\])/.freeze

      # A pattern that matches the comma in a (typically date) value.
      RE_COOKIE_COMMA = /,(?=#{RE_WSP}?#{RE_NAME}=)/.freeze

      module_function

      def scan_dquoted(scanner)
        s = +""

        until scanner.eos?
          break if scanner.skip(/"/)

          if scanner.skip(/\\/)
            s << scanner.getch
          elsif scanner.scan(/[^"\\]+/)
            s << scanner.matched
          end
        end

        s
      end

      def scan_value(scanner, comma_as_separator = false)
        value = +""

        until scanner.eos?
          if scanner.scan(/[^,;"]+/)
            value << scanner.matched
          elsif scanner.skip(/"/)
            # RFC 6265 2.2
            # A cookie-value may be DQUOTE'd.
            value << scan_dquoted(scanner)
          elsif scanner.check(/;/)
            break
          elsif comma_as_separator && scanner.check(RE_COOKIE_COMMA)
            break
          else
            value << scanner.getch
          end
        end

        value.rstrip!
        value
      end

      def scan_name_value(scanner, comma_as_separator = false)
        name = scanner.scan(RE_NAME)
        name.rstrip! if name

        if scanner.skip(/=/)
          value = scan_value(scanner, comma_as_separator)
        else
          scan_value(scanner, comma_as_separator)
          value = nil
        end
        [name, value]
      end

      def call(set_cookie)
        scanner = StringScanner.new(set_cookie)

        # RFC 6265 4.1.1 & 5.2
        until scanner.eos?
          start = scanner.pos
          len = nil

          scanner.skip(RE_WSP)

          name, value = scan_name_value(scanner, true)
          value = nil if name.empty?

          attrs = {}

          until scanner.eos?
            if scanner.skip(/,/)
              # The comma is used as separator for concatenating multiple
              # values of a header.
              len = (scanner.pos - 1) - start
              break
            elsif scanner.skip(/;/)
              scanner.skip(RE_WSP)

              aname, avalue = scan_name_value(scanner, true)

              next if aname.empty? || value.nil?

              aname.downcase!

              case aname
              when "expires"
                # RFC 6265 5.2.1
                (avalue &&= Time.httpdate(avalue)) || next
              when "max-age"
                # RFC 6265 5.2.2
                next unless /\A-?\d+\z/.match?(avalue)

                avalue = Integer(avalue)
              when "domain"
                # RFC 6265 5.2.3
                # An empty value SHOULD be ignored.
                next if avalue.nil? || avalue.empty?
              when "path"
                # RFC 6265 5.2.4
                # A relative path must be ignored rather than normalizing it
                # to "/".
                next unless avalue.start_with?("/")
              when "secure", "httponly"
                # RFC 6265 5.2.5, 5.2.6
                avalue = true
              end
              attrs[aname] = avalue
            end
          end

          len ||= scanner.pos - start

          next if len > Cookie::MAX_LENGTH

          yield(name, value, attrs) if name && !name.empty? && value
        end
      end
    end
  end
end
