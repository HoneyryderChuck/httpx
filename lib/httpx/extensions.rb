# frozen_string_literal: true

require "uri"

module HTTPX
  unless Method.method_defined?(:curry)

    # Backport
    #
    # Ruby 2.1 and lower implement curry only for Procs.
    #
    # Why not using Refinements? Because they don't work for Method (tested with ruby 2.1.9).
    #
    module CurryMethods
      # Backport for the Method#curry method, which is part of ruby core since 2.2 .
      #
      def curry(*args)
        to_proc.curry(*args)
      end
    end
    Method.__send__(:include, CurryMethods)
  end

  unless String.method_defined?(:+@)
    # Backport for +"", to initialize unfrozen strings from the string literal.
    #
    module LiteralStringExtensions
      def +@
        frozen? ? dup : self
      end
    end
    String.__send__(:include, LiteralStringExtensions)
  end

  unless Numeric.method_defined?(:positive?)
    # Ruby 2.3 Backport (Numeric#positive?)
    #
    module PosMethods
      def positive?
        self > 0
      end
    end
    Numeric.__send__(:include, PosMethods)
  end

  unless Numeric.method_defined?(:negative?)
    # Ruby 2.3 Backport (Numeric#negative?)
    #
    module NegMethods
      def negative?
        self < 0
      end
    end
    Numeric.__send__(:include, NegMethods)
  end

  module RegexpExtensions
    # If you wonder why this is there: the oauth feature uses a refinement to enhance the
    # Regexp class locally with #match? , but this is never tested, because ActiveSupport
    # monkey-patches the same method... Please ActiveSupport, stop being so intrusive!
    # :nocov:
    refine(Regexp) do
      def match?(*args)
        !match(*args).nil?
      end
    end
  end

  module URIExtensions
    refine URI::Generic do
      def non_ascii_hostname
        @non_ascii_hostname
      end

      def non_ascii_hostname=(hostname)
        @non_ascii_hostname = hostname
      end

      def authority
        port_string = port == default_port ? nil : ":#{port}"
        "#{host}#{port_string}"
      end

      def origin
        "#{scheme}://#{authority}"
      end

      def altsvc_match?(uri)
        uri = URI.parse(uri)

        origin == uri.origin || begin
          case scheme
          when "h2"
            (uri.scheme == "https" || uri.scheme == "h2") &&
            host == uri.host &&
            (port || default_port) == (uri.port || uri.default_port)
          else
            false
          end
        end
      end
    end
  end
end
