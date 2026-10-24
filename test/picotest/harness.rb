module PicotestHarness
  REPO_ROOT     = File.expand_path("../..", __dir__)
  PICORUBY_ROOT = ENV["PICORUBY_ROOT"] || File.join(REPO_ROOT, "vendor", "R2P2-darwin", "vendor", "picoruby")
  PICORUBY_VM   = File.join(REPO_ROOT, "build", "picotest", "host-picotest", "bin", "picoruby")

  GEM_DIR     = File.join(REPO_ROOT, "mrbgems", "picoruby-phomemo-thermal-printer")
  GEM_MRBLIB  = Dir[File.join(GEM_DIR, "mrblib", "**", "*.rb")].sort
  GEM_PACKET  = File.join(GEM_DIR, "ports", "darwin", "packet.rb")
  FAKE_TRANSPORT = File.join(GEM_DIR, "test", "mock", "fake_transport.rb")
  CLI_RB      = File.join(REPO_ROOT, "cli", "phomemo_cli.rb")

  GEM_LOAD_FILES = [*GEM_MRBLIB, GEM_PACKET, FAKE_TRANSPORT]

  SUITES = {
    "gem" => {
      dir: File.join(GEM_DIR, "test"),
      load_files: lambda { GEM_LOAD_FILES },
    },
    "cli" => {
      dir: File.join(REPO_ROOT, "test", "cli"),
      load_files: lambda { [*GEM_LOAD_FILES, CLI_RB] },
    },
  }.freeze

  module_function

  def run(filter: nil, suite: nil)
    require File.join(PICORUBY_ROOT, "mrbgems", "picoruby-picotest", "mrblib", "picotest.rb")
    ENV["RUBY"] = ENV["PICOTEST_VM"] || PICORUBY_VM
    ENV["THERMAL_PRINTER_REPO_ROOT"] = REPO_ROOT

    names = suite ? [suite] : SUITES.keys
    errors = 0
    names.each do |name|
      s = SUITES.fetch(name) { abort "unknown SUITE=#{name} (expected one of #{SUITES.keys.join(' / ')})" }
      puts "== picotest suite: #{name} =="
      next puts("(no #{s[:dir]}, skipped)") unless Dir.exist?(s[:dir])
      errors += Picotest::Runner.new(
        s[:dir],
        filter: filter,
        load_path: nil,
        load_files: s[:load_files].call.select { |f| File.exist?(f) },
      ).run
    end
    errors
  end
end
