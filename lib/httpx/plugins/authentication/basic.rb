# frozen_string_literal: true

require "base64"

module HTTPX
  module Plugins
    module Authentication
      class Basic
        def initialize(user, password, **)
          @user = user
          @password = password
        end

        def can_authenticate?(authenticate)
          authenticate && /Basic .*/.match?(authenticate)
        end

        def authenticate(*)
          "Basic #{Base64.strict_encode64("#{@user}:#{@password}")}"
        end
      end
    end
  end
end
