require "rbconfig"

ROOT         = File.expand_path(__dir__)
RD           = File.join(ROOT, "vendor", "R2P2-darwin")
PICORUBY_SRC = File.join(RD, "vendor", "picoruby")
GEM_DIR      = File.join(ROOT, "vendor", "picoruby-phomemo-thermal-printer")
TEST_VM      = File.join(ROOT, "build", "picotest", "host-picotest", "bin", "picoruby")

ENV["PATH"] = [RbConfig::CONFIG["bindir"], "/usr/bin", ENV["PATH"]].join(":")
