# frozen_string_literal: true

module HTTPX
  unless ENV.keys.grep(/\Ahttps?_proxy\z/i).empty?
    proxy_session = plugin(:proxy)
    remove_const(:Session)
    const_set(:Session, proxy_session.class)

    # redefine the default options static var, which needs to
    # refresh options_class
    options = proxy_session.class.default_options.to_hash
    options.freeze
    original_verbosity = $VERBOSE
    $VERBOSE = nil
    Options.send(:const_set, :DEFAULT_OPTIONS, options)
    $VERBOSE = original_verbosity
  end

  # :nocov:
  if Session.default_options.debug_level > 2
    proxy_session = plugin(:internal_telemetry)
    remove_const(:Session)
    const_set(:Session, proxy_session.class)
  end
  # :nocov:
end
