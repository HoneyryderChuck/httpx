# frozen_string_literal: true

require "base64"

module HTTPX
  module Plugins
    module Authentication
      class Basic
        def initialize(user, password, *)
          @user = user
          @password = password
        end

        def can_authenticate?(response)
          !response.is_a?(ErrorResponse) &&
            response.status == 401 && response.headers.key?("www-authenticate") &&
            /Basic .*/.match?(response.headers["www-authenticate"])
        end

        def authenticate(*)
          "Basic #{Base64.strict_encode64("#{@user}:#{@password}")}"
        end
      end
    end
  end
end
