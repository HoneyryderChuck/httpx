# frozen_string_literal: true

require_relative "test_helper"

class TimersTest < Minitest::Test
  def test_empty_timers_have_no_wait_interval
    timers = HTTPX::Timers.new

    assert timers.wait_interval.nil?
    assert timers.empty?
  end

  def test_cancelled_deadlines_do_not_leave_a_wait_interval
    timers = HTTPX::Timers.new
    [1, 30, 60].each do |seconds|
      timers.after(seconds) { raise "cancelled timer fired" }.cancel
    end

    assert timers.wait_interval.nil?
    assert timers.empty?
    timers.fire
  end

  def test_wait_interval_selects_the_next_active_deadline
    timers = HTTPX::Timers.new
    timers.after(1) { raise "cancelled timer fired" }.cancel
    timers.after(30) {}

    assert timers.wait_interval == 30
    assert !timers.empty?
  end

  def test_cancellation_preserves_other_callbacks_at_the_same_deadline
    timers = HTTPX::Timers.new
    fired = []
    cancelled = timers.after(0) { raise "cancelled timer fired" }
    timers.after(0) { fired << :active }
    cancelled.cancel

    assert timers.wait_interval.nil?
    assert fired == [:active]
    assert timers.empty?
    timers.fire
    assert fired == [:active]
  end

  def test_due_callbacks_run_before_selecting_the_next_interval
    timers = HTTPX::Timers.new
    fired = []
    timers.after(0) { fired << :due }
    timers.after(5) { fired << :later }

    assert timers.wait_interval == 5
    assert fired == [:due]
    assert !timers.empty?
  end

  def test_selector_does_not_sleep_on_a_cancelled_deadline_without_sockets
    selector = HTTPX::Selector.new
    waits = []
    selector.define_singleton_method(:sleep) { |interval| waits << interval }
    selector.after(60) { raise "cancelled timer fired" }.cancel

    selector.next_tick

    assert waits.empty?, "selector slept on a cancelled deadline: #{waits.inspect}"
    assert selector.empty?
  end

  def test_selector_still_waits_for_and_fires_an_active_deadline
    selector = HTTPX::Selector.new
    fired = false
    selector.after(0.001) { fired = true }

    selector.next_tick until selector.empty?

    assert fired
    assert selector.empty?
  end
end
