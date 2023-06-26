# frozen_string_literal: true

module HTTPX
  unless ENV.keys.grep(/\Ahttps?_proxy\z/i).empty?
    proxy_session = plugin(:proxy)
    remove_const(:Session)
    const_set(:Session, proxy_session.class)

    # redefine the default options static var, which needs to
    # refresh options_class
    options = proxy_session.class.default_options.to_hash
    original_verbosity = $VERBOSE
    $VERBOSE = nil
    const_set(:Options, proxy_session.class.default_options.options_class)
    options[:options_class] = Class.new(options[:options_class])
    options.freeze
    Options.send(:const_set, :DEFAULT_OPTIONS, options)
    Session.instance_variable_set(:@default_options, Options.new(options))
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
