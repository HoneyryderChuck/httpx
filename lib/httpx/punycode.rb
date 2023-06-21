# frozen_string_literal: true

module HTTPX
  module Punycode
    module_function

    begin
      require "idnx"

      def encode_hostname(hostname)
        Idnx.to_punycode(hostname)
      end
    rescue LoadError
      def encode_hostname(hostname)
        warn "#{hostname} cannot be converted to punycode. Install the " \
             "\"idnx\" gem: https://github.com/HoneyryderChuck/idnx"

        hostname
      end
    end
  end
end
