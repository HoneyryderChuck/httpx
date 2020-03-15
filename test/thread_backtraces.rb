# frozen_string_literal: true

BACKTRACE_HANDLER = lambda do
  Thread.list.each do |thread|
    warn "Thread TID-#{(thread.object_id ^ ::Process.pid).to_s(36)} #{thread.name}"
    if thread.backtrace
      warn thread.backtrace
    else
      warn "<no backtrace available>"
    end
  end
end

Signal.trap("USR2", BACKTRACE_HANDLER)
