# frozen_string_literal: true

module HTTPX
  module Plugins
    module Authentication
      module InstanceMethods
        def authentication(token)
          headers("authorization" => token)
        end
      end
    end
    register_plugin :authentication, Authentication
  end
end
