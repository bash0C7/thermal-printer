require "open3"
require_relative "../tools/e2e_judge"

E2E_PREVIEW_EXPECTATIONS = File.join(ROOT, "test", "e2e", "preview")
E2E_PREVIEW_CARDS        = File.join(ROOT, "test", "fixtures", "cards")
E2E_PREVIEW_BUILD        = File.join(ROOT, "build", "e2e", "preview")
E2E_CLI                  = File.join(ROOT, "bin", "phomemo-print")

def e2e_run(*command)
  output, status = Open3.capture2e(*command)
  abort "#{command.join(' ')} failed (exit #{status.exitstatus}):\n#{output}" unless status.success?
  output
end

def e2e_preview_png(name)
  card = File.join(E2E_PREVIEW_CARDS, "#{name}.json")
  abort "#{card} not found for expectation #{name}" unless File.exist?(card)
  pbm = File.join(E2E_PREVIEW_BUILD, "#{name}.pbm")
  png = File.join(E2E_PREVIEW_BUILD, "#{name}.png")
  e2e_run(SWIFT, "run", "--package-path", CORE_DIR, "thermal-pbm", "--card", card, pbm)
  e2e_run({ "PHOMEMO_PICORUBY" => APP_VM }, E2E_CLI, "--dry-run", "--png", png, pbm)
  e2e_check_png_header(png)
  png
end

def e2e_check_png_header(png)
  header = File.binread(png, 26)
  width = header.byteslice(16, 4).unpack1("N")
  bit_depth = header.getbyte(24)
  color_type = header.getbyte(25)
  return if width == 384 && bit_depth == 1 && color_type == 3
  abort "#{png}: expected a 384 px wide 1-bit palette PNG, got width #{width}, bit depth #{bit_depth}, color type #{color_type}"
end

namespace :test do
  namespace :e2e do
    desc "Judge the CLI dry-run preview PNG of each card fixture against test/e2e/preview/<name>.md with claude -p"
    task :preview do
      abort "#{APP_VM} not found - run `rake vm:build` first" unless File.executable?(APP_VM)
      expectations = Dir[File.join(E2E_PREVIEW_EXPECTATIONS, "*.md")].sort
      abort "no expectations under #{E2E_PREVIEW_EXPECTATIONS}" if expectations.empty?
      mkdir_p E2E_PREVIEW_BUILD

      failed = []
      expectations.each do |file|
        name = File.basename(file, ".md")
        png = e2e_preview_png(name)
        verdict = E2eJudge.judge(png, File.read(file))
        File.write(File.join(E2E_PREVIEW_BUILD, "#{name}.judge.txt"), verdict.output)
        if verdict.pass
          puts "PASS #{name} (#{png})"
        else
          puts "FAIL #{name} (#{png}): #{verdict.reason}"
          failed << name
        end
      end
      abort "e2e preview failed: #{failed.join(', ')}" unless failed.empty?
    end
  end

  desc "Run the E2E layer (judged by claude -p; spends tokens)"
  task e2e: "test:e2e:preview"
end
