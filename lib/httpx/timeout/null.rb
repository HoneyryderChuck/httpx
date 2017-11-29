# frozen_string_literal: true

module HTTPX::Timeout
  class Null
    def initialize(**)
    end

    def ==(other)
      other.is_a?(Null)
    end

    def connect
      yield
    end

    def timeout
      nil
    end
  end
end
