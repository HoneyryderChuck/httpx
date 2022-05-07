# frozen_string_literal: true

require "base64"

module HTTPX
  module Plugins
    module Authentication
      class Socks5
        def initialize(user, password, **)
          @user = user
          @password = password
        end

        def can_authenticate?(*)
          @user && @password
        end

        def authenticate(*)
          [0x01, @user.bytesize, @user, @password.bytesize, @password].pack("CCA*CA*")
        end
      end
    end
  end
end
