module PicotestHarness
  REPO_ROOT     = File.expand_path("../..", __dir__)
  PICORUBY_ROOT = ENV["PICORUBY_ROOT"] || File.join(REPO_ROOT, "vendor", "R2P2-darwin", "vendor", "picoruby")
  PICORUBY_VM   = File.join(REPO_ROOT, "build", "picotest", "host-picotest", "bin", "picoruby")

  GEM_DIR     = File.join(REPO_ROOT, "vendor", "picoruby-phomemo-thermal-printer")
  GEM_BLE_BOUND = File.join(GEM_DIR, "mrblib", "phomemo_thermal_printer", "transport.rb")
  GEM_MRBLIB  = Dir[File.join(GEM_DIR, "mrblib", "**", "*.rb")].sort - [GEM_BLE_BOUND]
  FAKE_TRANSPORT = File.join(GEM_DIR, "test", "mock", "fake_transport.rb")
  CLI_RB      = File.join(REPO_ROOT, "cli", "phomemo_cli.rb")

  GEM_LOAD_FILES = [*GEM_MRBLIB, FAKE_TRANSPORT]

  PROBE_GEM_DIR = File.expand_path("../picoruby-debug-probe", REPO_ROOT)
  CANVAS_GEM_DIR = File.expand_path("../picoruby-text-canvas", REPO_ROOT)

  SUITES = {
    "cli" => {
      dir: File.join(REPO_ROOT, "test", "cli"),
      load_files: lambda { [*GEM_LOAD_FILES, CLI_RB] },
    },
    "probe" => {
      dir: File.join(PROBE_GEM_DIR, "test"),
      load_files: lambda { Dir[File.join(PROBE_GEM_DIR, "mrblib", "**", "*.rb")].sort },
    },
    "canvas" => {
      dir: File.join(CANVAS_GEM_DIR, "test"),
      load_files: lambda { [*GEM_LOAD_FILES, *Dir[File.join(CANVAS_GEM_DIR, "mrblib", "**", "*.rb")].sort] },
    },
  }.freeze

  module_function

  def run(filter: nil, suite: nil)
    abort "#{GEM_DIR} not found - run `rake vendor:setup` first" unless Dir.exist?(GEM_DIR)
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
