SPIKE_VM       = File.join(RD, "build", "host", "bin", "picoruby")
SPIKE_APP      = File.expand_path("~/Applications/ThermalPrinterSpike.app")
SPIKE_LAUNCHER = File.expand_path("~/Applications/ThermalPrinterSpikeLauncher.app")

namespace :spike do
  desc "Build ~/Applications/ThermalPrinterSpike.app around the built VM (route 2)"
  task :app do
    abort "#{SPIKE_VM} not found - run `rake vm:build` first" unless File.exist?(SPIKE_VM)
    macos = File.join(SPIKE_APP, "Contents", "MacOS")
    mkdir_p macos
    cp SPIKE_VM, File.join(macos, "picoruby")
    cp File.join(ROOT, "spike", "ThermalPrinterSpike-Info.plist"), File.join(SPIKE_APP, "Contents", "Info.plist")
    sh "codesign", "--force", "--deep", "-s", "-", "-r=designated => identifier \"com.bash0c7.thermalprinterspike\"", SPIKE_APP
  end

  desc "Build ~/Applications/ThermalPrinterSpikeLauncher.app that runs a bundled picoruby as a child (route 4)"
  task :launcher do
    abort "#{SPIKE_VM} not found - run `rake vm:build` first" unless File.exist?(SPIKE_VM)
    build = File.join(ROOT, "build", "launcher")
    mkdir_p build
    sh "/usr/bin/swiftc", "-O", "-o", File.join(build, "launcher"), File.join(ROOT, "spike", "launcher", "main.swift")
    macos = File.join(SPIKE_LAUNCHER, "Contents", "MacOS")
    res   = File.join(SPIKE_LAUNCHER, "Contents", "Resources")
    mkdir_p macos
    mkdir_p res
    cp File.join(build, "launcher"), File.join(macos, "launcher")
    cp SPIKE_VM, File.join(res, "picoruby")
    cp File.join(ROOT, "spike", "scan.rb"), File.join(res, "scan.rb")
    cp File.join(ROOT, "spike", "gatt_dump_probe.rb"), File.join(res, "gatt_dump_probe.rb")
    cp File.join(ROOT, "spike", "launcher", "Info.plist"), File.join(SPIKE_LAUNCHER, "Contents", "Info.plist")
    sh "codesign", "--force", "--deep", "-s", "-", "-r=designated => identifier \"com.bash0c7.thermalprinterspike.launcher\"", SPIKE_LAUNCHER
  end
end
