# frozen_string_literal: true

if RUBY_VERSION < "3.3.0"
  require "base64"
elsif !defined?(Base64)
  module HTTPX
    # require "base64" will not be a default gem after ruby 3.4.0
    module Base64
      module_function

      def decode64(str)
        str.unpack1("m")
      end

      def strict_encode64(bin)
        [bin].pack("m0")
      end

      def urlsafe_encode64(bin, padding: true)
        str = strict_encode64(bin)
        str.chomp!("==") or str.chomp!("=") unless padding
        str.tr!("+/", "-_")
        str
      end
    end
  end
end
