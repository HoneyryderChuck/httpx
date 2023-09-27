SimpleCov.start do
  command_name "Minitest"
  add_filter "/.bundle/"
  add_filter "/vendor/"
  add_filter "/test/"
  add_filter "/integration_tests/"
  add_filter "/regression_tests/"
  add_filter "/lib/httpx/plugins/internal_telemetry.rb"
  add_filter "/lib/httpx/base64.rb"
end
