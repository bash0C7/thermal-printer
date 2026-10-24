require "open3"
require "tmpdir"

module E2eJudge
  Verdict = Struct.new(:pass, :reason, :output)

  class RunnerError < StandardError; end

  VERDICT_PREFIX = /\AVERDICT:/
  VERDICT_FORMAT = /\AVERDICT:[ \t]+(PASS|FAIL)(?:[ \t]+(\S.*))?\z/

  def self.prompt(png_path, expectation)
    <<~PROMPT
      You are the judge of an end-to-end test of a thermal-printer preview.
      Open the image with the Read tool and look at it carefully: #{png_path}

      Expectation:
      <<<
      #{expectation.strip}
      >>>

      Check every fact in the expectation against the image. Judge only what you can see.
      If any fact is missing, wrong or unreadable, the verdict is FAIL.
      Write a short account of what you see, then end your reply with exactly one final line, either
      VERDICT: PASS
      or
      VERDICT: FAIL <one-line reason>
    PROMPT
  end

  def self.parse(output)
    lines = output.to_s.lines.map(&:rstrip)
    lines.pop while lines.last == ""
    marked = lines.select { |line| line.match?(VERDICT_PREFIX) }
    return Verdict.new(false, "no verdict line", output) if marked.empty?
    return Verdict.new(false, "more than one verdict line", output) if marked.size > 1
    return Verdict.new(false, "verdict line is not the last line", output) unless lines.last == marked.first
    match = VERDICT_FORMAT.match(marked.first)
    return Verdict.new(false, "ambiguous verdict line: #{marked.first}", output) unless match
    return Verdict.new(true, "", output) if match[1] == "PASS" && match[2].nil?
    return Verdict.new(false, "ambiguous verdict line: #{marked.first}", output) if match[1] == "PASS"
    Verdict.new(false, match[2] || "no reason given", output)
  end

  def self.claude_command(png_dir)
    ["claude", "-p", "--tools", "Read", "--allowedTools", "Read", "--add-dir", png_dir,
     "--permission-mode", "dontAsk", "--no-session-persistence", "--disable-slash-commands"]
  end

  def self.run_claude(prompt, png_dir, capture: nil)
    Dir.mktmpdir("e2e-judge-") do |cwd|
      env = { "ANTHROPIC_API_KEY" => nil }
      command = claude_command(png_dir)
      stdout, stderr, status =
        if capture
          capture.call(env, *command, stdin_data: prompt, chdir: cwd)
        else
          Open3.capture3(env, *command, stdin_data: prompt, chdir: cwd)
        end
      raise RunnerError, "claude exited #{status.exitstatus}: #{stderr.strip}" unless status.success?
      stdout
    end
  end

  def self.judge(png_path, expectation, runner: nil)
    png = File.expand_path(png_path)
    text = prompt(png, expectation)
    dir = File.dirname(png)
    parse(runner ? runner.call(text, dir) : run_claude(text, dir))
  rescue RunnerError => e
    Verdict.new(false, e.message, "")
  end
end

if $PROGRAM_NAME == __FILE__
  png, expectation_file = ARGV
  abort "usage: ruby #{$PROGRAM_NAME} <image.png> <expectation.md>" unless png && expectation_file
  verdict = E2eJudge.judge(png, File.read(expectation_file))
  puts verdict.output
  puts(verdict.pass ? "PASS" : "FAIL #{verdict.reason}")
  exit(verdict.pass ? 0 : 1)
end
