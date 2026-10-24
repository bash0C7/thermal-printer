desc "Run the unit and integration layers"
task test: ["test:unit", "test:integration"]

namespace :test do
  desc "Run the unit layer (picotest suites, CRuby tool tests, check:send_paths, Swift unit tests)"
  task unit: ["test:ruby", "test:tools", "check:send_paths"] do
    sh SWIFT, "test", "--package-path", CORE_DIR, "--skip", "ThermalPrinterIntegrationTests"
  end

  desc "Run the integration layer against the product VM (CRuby tests under test/integration, Swift integration tests)"
  task :integration do
    abort "#{APP_VM} not found - run `rake vm:build` first" unless File.executable?(APP_VM)
    Dir[File.join(ROOT, "test", "integration", "*_test.rb")].sort.each do |file|
      sh RbConfig.ruby, file
    end
    sh SWIFT, "test", "--package-path", CORE_DIR, "--filter", "ThermalPrinterIntegrationTests"
  end

  desc "Run the picotest suites on the test VM. SUITE=<gem|cli>, FILTER=<file substring>"
  task ruby: "picotest:ensure_vm" do
    $LOAD_PATH.unshift File.join(ROOT, "test")
    require "picotest/harness"
    errors = PicotestHarness.run(filter: ENV["FILTER"], suite: ENV["SUITE"])
    abort "picotest failed: #{errors} error(s)" unless errors == 0
  end

  desc "Run the CRuby minitest files under test/tools"
  task :tools do
    Dir[File.join(ROOT, "test", "tools", "*_test.rb")].sort.each do |file|
      sh RbConfig.ruby, file
    end
  end
end
