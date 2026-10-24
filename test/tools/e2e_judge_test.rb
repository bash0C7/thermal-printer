require "minitest/autorun"
require "tmpdir"
require_relative "../../tools/e2e_judge"

class E2eJudgeTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  Status = Struct.new(:exitstatus) do
    def success? = exitstatus == 0
  end

  def test_prompt_contains_the_png_path_and_the_expectation
    text = E2eJudge.prompt("/tmp/x/github.png", "The header reads bash0C7/thermal-printer.")
    assert_includes text, "/tmp/x/github.png"
    assert_includes text, "The header reads bash0C7/thermal-printer."
  end

  def test_prompt_asks_for_a_single_final_verdict_line
    text = E2eJudge.prompt("/tmp/a.png", "x")
    assert_includes text, "VERDICT: PASS"
    assert_includes text, "VERDICT: FAIL <one-line reason>"
  end

  def test_parse_accepts_pass
    verdict = E2eJudge.parse("It looks right.\nVERDICT: PASS\n")
    assert verdict.pass
  end

  def test_parse_accepts_fail_with_a_reason
    verdict = E2eJudge.parse("No QR code.\nVERDICT: FAIL the QR code is missing\n")
    refute verdict.pass
    assert_equal "the QR code is missing", verdict.reason
  end

  def test_parse_tolerates_trailing_whitespace_and_blank_lines
    assert E2eJudge.parse("ok\nVERDICT: PASS  \t\n\n\n").pass
    assert E2eJudge.parse("ok\r\nVERDICT: PASS\r\n").pass
    verdict = E2eJudge.parse("ok\nVERDICT: FAIL too wide \n")
    assert_equal "too wide", verdict.reason
  end

  def test_parse_treats_a_missing_verdict_as_fail
    verdict = E2eJudge.parse("Looks fine to me.\n")
    refute verdict.pass
    assert_equal "no verdict line", verdict.reason
    refute E2eJudge.parse("").pass
    refute E2eJudge.parse(nil).pass
  end

  def test_parse_treats_duplicate_verdicts_as_fail
    verdict = E2eJudge.parse("VERDICT: PASS\nmore\nVERDICT: PASS\n")
    refute verdict.pass
    assert_equal "more than one verdict line", verdict.reason
    refute E2eJudge.parse("VERDICT: FAIL a\nVERDICT: PASS\n").pass
  end

  def test_parse_treats_a_verdict_that_is_not_last_as_fail
    verdict = E2eJudge.parse("VERDICT: PASS\nbut wait\n")
    refute verdict.pass
    assert_equal "verdict line is not the last line", verdict.reason
  end

  def test_parse_treats_ambiguous_verdict_lines_as_fail
    ["VERDICT: MAYBE", "VERDICT:", "VERDICT: PASS because it is nice", "VERDICT: pass", "VERDICT:PASS"].each do |line|
      refute E2eJudge.parse("text\n#{line}\n").pass, line
    end
  end

  def test_parse_ignores_a_verdict_phrase_inside_a_sentence
    assert E2eJudge.parse("I will finish with VERDICT: FAIL if wrong.\nVERDICT: PASS\n").pass
  end

  def test_parse_treats_a_bare_fail_as_fail_with_a_placeholder_reason
    verdict = E2eJudge.parse("VERDICT: FAIL\n")
    refute verdict.pass
    assert_equal "no reason given", verdict.reason
  end

  def test_judge_passes_the_prompt_and_the_png_directory_to_the_runner
    seen = nil
    runner = lambda do |prompt, dir|
      seen = [prompt, dir]
      "fine\nVERDICT: PASS\n"
    end
    verdict = E2eJudge.judge("/tmp/e2e/out/github.png", "has a header", runner: runner)
    assert verdict.pass
    assert_includes seen[0], "/tmp/e2e/out/github.png"
    assert_includes seen[0], "has a header"
    assert_equal "/tmp/e2e/out", seen[1]
    assert_includes verdict.output, "fine"
  end

  def test_judge_reports_a_runner_error_as_fail
    runner = ->(_prompt, _dir) { raise E2eJudge::RunnerError, "claude exited 1: boom" }
    verdict = E2eJudge.judge("/tmp/a.png", "x", runner: runner)
    refute verdict.pass
    assert_equal "claude exited 1: boom", verdict.reason
  end

  def test_claude_command_allows_only_read_and_the_png_directory
    command = E2eJudge.claude_command("/tmp/e2e/out")
    assert_equal ["claude", "-p"], command.first(2)
    assert_equal "Read", command[command.index("--tools") + 1]
    assert_equal "Read", command[command.index("--allowedTools") + 1]
    assert_equal "/tmp/e2e/out", command[command.index("--add-dir") + 1]
    assert_equal "dontAsk", command[command.index("--permission-mode") + 1]
  end

  def test_run_claude_uses_a_fresh_directory_outside_the_repo_and_sends_the_prompt_on_stdin
    seen = {}
    capture = lambda do |env, *command, **options|
      seen[:env] = env
      seen[:command] = command
      seen[:stdin] = options[:stdin_data]
      seen[:cwd] = options[:chdir]
      seen[:existed] = File.directory?(options[:chdir])
      ["VERDICT: PASS\n", "", Status.new(0)]
    end
    out = E2eJudge.run_claude("the prompt", "/tmp/e2e/out", capture: capture)
    assert_equal "VERDICT: PASS\n", out
    assert seen[:existed]
    refute File.exist?(seen[:cwd])
    refute seen[:cwd].start_with?(ROOT)
    assert_equal "the prompt", seen[:stdin]
    assert_equal E2eJudge.claude_command("/tmp/e2e/out"), seen[:command]
    assert_equal({ "ANTHROPIC_API_KEY" => nil }, seen[:env])
  end

  def test_run_claude_raises_when_claude_fails
    capture = ->(_env, *_command, **_options) { ["", "no auth\n", Status.new(1)] }
    error = assert_raises(E2eJudge::RunnerError) { E2eJudge.run_claude("p", "/tmp/x", capture: capture) }
    assert_equal "claude exited 1: no auth", error.message
  end
end
