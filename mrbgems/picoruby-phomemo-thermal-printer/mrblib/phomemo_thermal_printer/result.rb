module PhomemoThermalPrinter
  class Result
    VERSION = 1
    HINTS = {
      "not_found" => "T02 was not found. Press the power button to wake it, disconnect the official app, and check that Bluetooth access is allowed for this app.",
      "wrong_device" => "The device named T02 does not expose the printer service ff00. Nothing was sent.",
      "busy" => "Another phomemo-print is running. Wait for it to finish.",
      "disconnected" => "The printer disconnected while printing. Wake it and print again.",
      "status_unavailable" => "No status reply arrived. On the first run, accept the macOS pairing prompt, then run again. If it persists, pair the T02 in System Settings > Bluetooth.",
      "paper_out" => "The printer is out of paper. Load paper and close the cover.",
      "cover_open" => "The cover is open. Close it.",
      "overheat" => "The printer is too hot. Let it cool down.",
      "low_battery" => "The battery is at 5% or less. Charge the printer.",
    }

    attr_reader :mode, :error, :hint, :warnings, :completion_state, :after_send_ms
    attr_accessor :status, :job, :notify, :elapsed_ms

    def self.failure(mode, error, hint: nil, elapsed_ms: 0)
      result = new(mode)
      result.fail_with(error, hint)
      result.elapsed_ms = elapsed_ms
      result
    end

    def initialize(mode)
      @mode = mode
      @error = nil
      @hint = nil
      @warnings = []
      @status = nil
      @job = nil
      @notify = nil
      @completion_state = nil
      @after_send_ms = nil
      @elapsed_ms = 0
    end

    def ok
      @error.nil?
    end

    def fail_with(error, hint = nil)
      @error = error
      @hint = hint || HINTS[error]
    end

    def add_warning(name)
      i = 0
      while i < @warnings.size
        return if @warnings[i] == name
        i += 1
      end
      @warnings << name
    end

    def complete(state, after_send_ms)
      @completion_state = state
      @after_send_ms = after_send_ms
    end

    def to_h(exit_code:)
      completion = nil
      completion = {"state" => @completion_state, "after_send_ms" => @after_send_ms} if @completion_state
      {
        "version" => VERSION,
        "mode" => @mode,
        "ok" => ok,
        "error" => @error,
        "exit_code" => exit_code,
        "hint" => @hint,
        "warnings" => @warnings,
        "status" => @status,
        "job" => @job,
        "notify" => @notify,
        "completion" => completion,
        "elapsed_ms" => @elapsed_ms,
      }
    end
  end
end
