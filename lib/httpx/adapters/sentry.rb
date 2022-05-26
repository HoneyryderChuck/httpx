# frozen_string_literal: true

module HTTPX::Plugins
  module Sentry
  end
end

Sentry.register_patch do
  sentry_session = ::HTTPX.plugin(HTTPX::Plugins::Sentry)

  HTTPX.send(:remove_const, :Session)
  HTTPX.send(:const_set, :Session, sentry_session.class)
end
