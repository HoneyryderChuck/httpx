# frozen_string_literal: true

require_relative "test"

class DigestServer < TestServer
  def get_passwd(user)
    @htpasswd.get_passwd("Wacky World", user, false)
  end

  def initialize(options = {})
    algorithm = options.delete(:algorithm)
    super

    Tempfile.create("test_httpx_digest_auth") do |tmpfile|
      tmpfile.close
      @htpasswd = WEBrick::HTTPAuth::Htpasswd.new(tmpfile.path)
      @htpasswd.auth_type = WEBrick::HTTPAuth::DigestAuth
      @htpasswd.set_passwd("Wacky World", "user", "pass")
      @htpasswd.flush

      authenticator = WEBrick::HTTPAuth::DigestAuth.new(Realm: "Wacky World", UserDB: @htpasswd, Algorithm: algorithm, Logger: logger)

      mount_proc("/") do |req, res|
        authenticator.authenticate(req, res)
        res.status = 200
        res.body = "yay"
      end
    end
  end
end
