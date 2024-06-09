# frozen_string_literal: true

require_relative "test"

class Redirector307Server < TestServer
  class RedirectPostApp < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(_req, res) # rubocop:disable Naming/MethodName
      res.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/")
    end
  end

  class PostApp < WEBrick::HTTPServlet::AbstractServlet
    def do_POST(_req, res) # rubocop:disable Naming/MethodName
      res.body = "ok"
    end
  end

  def initialize(options = {})
    super
    mount("/", PostApp)
    mount("/307", RedirectPostApp)
  end
end
