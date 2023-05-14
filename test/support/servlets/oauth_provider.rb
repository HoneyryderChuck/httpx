# frozen_string_literal: true

require "json"
require "uri"
require_relative "test"

class OAuthProviderServer < TestServer
  attr_reader :metadata

  class Token < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(req, res) # rubocop:disable Naming/MethodName
      body = URI.decode_www_form(req.body).to_h
      user = pass = nil

      if req["authorization"]
        WEBrick::HTTPAuth.basic_auth(req, res, "My Realm") do |u, p|
          # block should return true if
          # authentication token is valid
          u == "CLIENT_ID" && p == "SECRET"
        end
        user = "CLIENT_ID"
        pass = "SECRET"
      else
        user = body["client_id"]
        pass = body["client_secret"]
      end

      res["content-type"] = "application/json"
      case body["grant_type"]
      when "client_credentials"
        if user == "CLIENT_ID" && pass == "SECRET"
          res.body = JSON.dump({ "access_token" => "CLIENT-CREDS-AUTH", "expires_in" => 3600, "token_type" => "bearer" })
          nil
        end
      when "refresh_token"
        if user == "CLIENT_ID" && pass == "SECRET" && body["refresh_token"] == "REFRESH_TOKEN"
          res.body = JSON.dump({ "access_token" => "REFRESH-TOKEN-AUTH", "expires_in" => 3600, "token_type" => "bearer" })
          nil
        end
      else
        raise "unsupported"
      end
    end
  end

  def initialize(*)
    super
    @metadata = {
      "issuer" => origin,
      "authorization_endpoint" => "#{origin}/authorize",
      "token_endpoint" => "#{origin}/token",
      "token_endpoint_auth_methods_supported" => %w[client_secret_basic client_secret_post private_key_jwt],
      "token_endpoint_auth_signing_alg_values_supported" => %w[RS256 ES256],
      "userinfo_endpoint" => "#{origin}/userinfo",
      "grant_types_supported" => %w[authorization_code implicit client_credentials],
      "jwks_uri" => "#{origin}/jwks.json",
      "registration_endpoint" => "#{origin}/register",
      "scopes_supported" => %w[openid profile email address phone offline_access],
      "response_types_supported" => ["code", "code token"],
      "service_documentation" => "#{origin}/service_documentation.html",
      "ui_locales_supported" => %w[en-US en-GB en-CA fr-FR fr-CA],
    }

    mount_proc("/.well-known/oauth-authorization-server") do |_req, res|
      res["Content-Type"] = "application/json"
      res.body = JSON.dump(metadata)
    end
    mount("/token", Token)

    mount_proc "/client-credentials-authed" do |req, res|
      if (auth = req["authorization"]) &&
         (token = auth[/Bearer (.+)/, 1]) &&
         token == "CLIENT-CREDS-AUTH"
        res.status = 200
        res.body = "yay"
      else
        res.status = 401
        res.body = "boo"
      end
    end

    mount_proc "/refresh-token-authed" do |req, res|
      if (auth = req["authorization"]) &&
         (token = auth[/Bearer (.+)/, 1]) &&
         token == "REFRESH-TOKEN-AUTH"
        res.status = 200
        res.body = "yay"
      else
        res.status = 401
        res.body = "boo"
      end
    end
  end
end
