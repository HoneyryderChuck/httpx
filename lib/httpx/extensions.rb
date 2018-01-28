# frozen_string_literal: true

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
