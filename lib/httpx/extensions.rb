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
    module CurryMethods # :nodoc:
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

  module URIExtensions
    URI_KLASSES = case RUBY_ENGINE
    when "jruby"
      [URI::Generic, URI::HTTP, URI::HTTPS]
    else
      [URI::Generic]
    end

    URI_KLASSES.each do |klass|
      refine klass do
        def authority
          port_string = port == default_port ? nil : ":#{port}"
          "#{host}#{port_string}"
        end

        def origin
          "#{scheme}://#{authority}"
        end

        def altsvc_match?(uri)
          uri = URI.parse(uri)
          self == uri || begin
            case scheme
            when 'h2'
              uri.scheme == "https" &&
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
end