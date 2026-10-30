module DualkeyQemu
  FAIL_PATTERNS = [/Guru Meditation/, /abort\(\)/, /Rebooting\.\.\./, /assert failed/, /stack overflow/].freeze
  ERROR_CLASS_PATTERN = /\((?:[A-Z]\w*::)*[A-Z]\w*(?:Error|Exception)\)\s*$|^Error: |^Exception\(vm_id=/
  PROBE_MARKER = "DUALKEY_PROBE_OK"
  APP_LOADED = "Loading app.mrb"
  SHELL_PROMPT = "$> "

  Verdict = Struct.new(:pass, :message, :decided)

  module_function

  def failure(text)
    FAIL_PATTERNS.each do |pattern|
      match = text[pattern]
      return "boot log shows #{match.inspect}" if match
    end
    text.each_line do |line|
      return "boot log shows #{line.strip.inspect}" if line.match?(ERROR_CLASS_PATTERN)
    end
    nil
  end

  def probe(log)
    text = log.to_s
    marker_at = text.index(PROBE_MARKER)
    prompt_at = marker_at && text.index(SHELL_PROMPT, marker_at)
    text = text[0, prompt_at + SHELL_PROMPT.size] if prompt_at
    problem = failure(text)
    return Verdict.new(false, problem, true) if problem
    return Verdict.new(false, "no marker", false) unless marker_at
    return Verdict.new(true, "marker #{PROBE_MARKER} found and the shell prompt followed", true) if prompt_at
    Verdict.new(false, "marker #{PROBE_MARKER} found but no shell prompt after it", false)
  end

  def app(log, elapsed_s:, hold_s:)
    text = log.to_s
    problem = failure(text)
    return Verdict.new(false, problem, true) if problem
    loaded_at = text.index(APP_LOADED)
    return Verdict.new(false, "app not loaded yet", false) unless loaded_at
    return Verdict.new(false, "the shell prompt returned, so the app exited", true) if text.index(SHELL_PROMPT, loaded_at)
    return Verdict.new(false, "app running, #{hold_s - elapsed_s} s left", false) if elapsed_s < hold_s
    Verdict.new(true, "app loaded and stayed running for #{hold_s} s", true)
  end
end
