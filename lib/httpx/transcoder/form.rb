# frozen_string_literal: true

require "http/form_data"

module HTTPX::Transcoder
  module Form
    module_function

    def encode(form)
      HTTP::FormData.create(form)
    end
  end
  register "form", Form
end
