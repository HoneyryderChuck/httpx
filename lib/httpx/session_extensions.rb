# frozen_string_literal: true

module HTTPX
  unless ENV.keys.grep(/\Ahttps?_proxy\z/i).empty?
    proxy_session = plugin(:proxy)
    remove_const(:Session)
    const_set(:Session, proxy_session.class)
    remove_const(:Options)
    const_set(:Options, proxy_session.class.default_options.class)
  end

  # :nocov:
  if Session.default_options.debug_level > 2
    proxy_session = plugin(:internal_telemetry)
    remove_const(:Session)
    const_set(:Session, proxy_session.class)
  end
  # :nocov:
end
