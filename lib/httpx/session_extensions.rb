# frozen_string_literal: true

module HTTPX
  unless ENV.keys.grep(/\Ahttps?_proxy\z/i).empty?
    proxy_session = plugin(:proxy)
    ::HTTPX.send(:remove_const, :Session)
    ::HTTPX.send(:const_set, :Session, proxy_session.class)
  end

  # :nocov:
  if Session.default_options.debug_level > 2
    proxy_session = plugin(:internal_telemetry)
    ::HTTPX.send(:remove_const, :Session)
    ::HTTPX.send(:const_set, :Session, proxy_session.class)
  end
  # :nocov:
end
