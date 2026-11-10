# frozen_string_literal: true

# counts the request timeouts registrations which are still live for each request (the callbacks of
# previous registrations are dropped when the request transitions back to idle, i.e. when rerouted).
module RequestTimeoutsRegistrations
  module RequestMethods
    attr_writer :timeouts_registrations

    def timeouts_registrations
      @timeouts_registrations ||= 0
    end

    def transition(nextstate)
      super

      @timeouts_registrations = 0 if nextstate == :idle
    end
  end

  module ConnectionMethods
    private

    def set_request_timeouts(request)
      request.timeouts_registrations += 1
      super
    end
  end
end
