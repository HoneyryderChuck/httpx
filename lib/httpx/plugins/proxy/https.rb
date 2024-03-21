# frozen_string_literal: true

module HTTPX
  module Plugins
    module Proxy
      module HTTPS
        class << self
          def load_dependencies(klass)
            klass.plugin(:"proxy/http") unless defined?(HTTP)
          end

          def extra_options(options)
            options.merge(supported_proxy_protocols: options.supported_proxy_protocols + %w[https])
          end
        end
      end
    end
    register_plugin :"proxy/https", Proxy::HTTPS
  end
end
