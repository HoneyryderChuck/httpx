# frozen_string_literal: true

require_relative "test_helper"

class TimersTest < Minitest::Test
  def test_timers_wait_interval
    timers = HTTPX::Timers.new

    assert timers.wait_interval.nil?
    assert timers.empty?

    # cancelled timers do not set a wait interval
    [1, 30, 60].each do |seconds|
      timers.after(seconds) { raise "cancelled timer fired" }.cancel
    end

    assert timers.wait_interval.nil?
    assert timers.empty?

    timers.after(30) {}

    assert timers.wait_interval == 30
    assert !timers.empty?
  end

  def timers_cancelling_timer_callbacks_keeps_other_callbacks
    timers = HTTPX::Timers.new
    fired = []
    cancelled = timers.after(0) { raise "cancelled timer fired" }
    timers.after(0) { fired << :active }
    cancelled.cancel

    assert timers.wait_interval.nil?
    assert fired == [:active]
    assert timers.empty?
  end
end
