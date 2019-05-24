# frozen_string_literal: true

# patch to make the ssh proxy test work
#
# problem: net-ssh needs the gem `rbnacl` to use ed25519 keys. The gem only requires libsodium
#   to be available in the system, however, the last `rbnacl` version that works with ruby 2.1
#   requires `rbnacl-libsodium` gem to be installed. And this gem is taking too long to build in
#   the alpine docker images, timing out our ruby 2.1 CI tests.
#
# solution: monkey-patch the variable which indicates the lib name to the FFI libsodium bindings.
#   the values are the same as in the latest version.
#
if RUBY_VERSION < "2.2" && RUBY_PLATFORM == "x86_64-linux-musl"
  RBNACL_LIBSODIUM_GEM_LIB_PATH = ["sodium", "libsodium.so.18", "libsodium.so.23"].freeze
end
