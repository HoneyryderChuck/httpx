# frozen_string_literal: true

# records the state of the connection every time the selector inspects it.
module SelectedConnectionStates
  module ConnectionMethods
    attr_reader :selected_states

    def initialize(*)
      super
      @selected_states = []
    end

    def interests
      @selected_states << @state
      super
    end

    def timeout
      @selected_states << @state
      super
    end
  end
end
