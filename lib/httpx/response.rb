# frozen_string_literal: true

require "forwardable"

module HTTPX
  class Response
    extend Forwardable

    attr_reader :status, :headers, :body

    def_delegator :@body, :to_s 
    def initialize(status, headers)
      @status = Integer(status)
      @headers = Headers.new(headers)
    end 

    def <<(data)
      (@body ||= +"") << data
    end

    
  end
end
