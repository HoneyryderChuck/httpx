SimpleCov.start do
  command_name "Minitest"
  add_filter "/.bundle/"
  add_filter "/vendor/"
  add_filter "/test/"
  add_filter "/lib/httpx/extensions.rb"
  add_filter "/lib/httpx/loggable.rb"
  add_filter "/lib/httpx/plugins/internal_telemetry.rb"
  add_filter "/lib/httpx/plugins/multipart/mime_type_detector.rb"
  add_filter "/lib/httpx/io/tls/"
  add_filter "/lib/httpx/io/tls.rb"
end
