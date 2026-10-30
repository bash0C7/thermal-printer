require "minitest/autorun"
require_relative "../../tools/dualkey/qemu_verdict"

class DualkeyQemuVerdictTest < Minitest::Test
  def test_probe_passes_with_marker_then_prompt
    assert DualkeyQemu.probe("boot\nDUALKEY_PROBE_OK\n$> ").pass
  end

  def test_probe_is_undecided_without_marker
    verdict = DualkeyQemu.probe("boot\n")
    refute verdict.decided
  end

  def test_probe_fails_on_guru_meditation
    verdict = DualkeyQemu.probe("Guru Meditation Error")
    refute verdict.pass
    assert verdict.decided
  end

  def test_probe_fails_on_ruby_error_line
    refute DualkeyQemu.probe("x (NoMemoryError)\n").pass
  end

  def test_probe_ignores_text_after_the_prompt
    assert DualkeyQemu.probe("DUALKEY_PROBE_OK\n$> Rebooting...").pass
  end

  def test_app_is_undecided_before_load
    refute DualkeyQemu.app("boot", elapsed_s: 5, hold_s: 30).decided
  end

  def test_app_fails_when_the_prompt_returns
    verdict = DualkeyQemu.app("Loading app.mrb\n$> ", elapsed_s: 5, hold_s: 30)
    refute verdict.pass
    assert verdict.decided
  end

  def test_app_waits_out_the_hold
    refute DualkeyQemu.app("Loading app.mrb\n", elapsed_s: 10, hold_s: 30).decided
  end

  def test_app_passes_after_the_hold
    assert DualkeyQemu.app("Loading app.mrb\n", elapsed_s: 30, hold_s: 30).pass
  end

  def test_app_fails_on_a_crash_after_loading
    refute DualkeyQemu.app("Loading app.mrb\nGuru Meditation", elapsed_s: 5, hold_s: 30).pass
  end
end
