# frozen_string_literal: true

Signal.trap("USR2") do
  warn "starting..."
  Thread.list.each do |thread|
    warn "Thread TID-#{(thread.object_id ^ ::Process.pid).to_s(36)} #{thread.name}"
    if thread.backtrace
      warn thread.backtrace
    else
      warn "<no backtrace available>"
    end
  end
end
