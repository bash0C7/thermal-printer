APP_DIR  = File.join(ROOT, "app")
CORE_DIR = File.join(APP_DIR, "Core")
SWIFT    = "/usr/bin/swift"
XCODEGEN = "/opt/homebrew/bin/xcodegen"

APP_XCODEBUILD  = "/usr/bin/xcodebuild"
APP_BUNDLE_ID   = "com.bash0c7.thermalprinter"
APP_DERIVED     = File.join(ROOT, "build", "app")
APP_PRODUCT     = File.join(APP_DERIVED, "Build", "Products", "Release", "ThermalPrinter.app")
APP_STAGE       = File.join(APP_DERIVED, "stage", "ThermalPrinter.app")
UITEST_DERIVED  = File.join(ROOT, "build", "uitest")
APP_INSTALLED   = File.expand_path("~/Applications/ThermalPrinter.app")
APP_VM          = File.join(RD, "build", "host", "bin", "picoruby")
APP_BLE_DYLIB   = File.join(PICORUBY_SRC, "mrbgems", "picoruby-ble", "ports", "darwin", "ext", ".build", "release", "libPicoBLEDarwin.dylib")
APP_CLI_SOURCES = %w[print.rb phomemo_cli.rb].map { |name| File.join(ROOT, "cli", name) }

namespace :app do
  desc "Generate app/ThermalPrinter.xcodeproj from app/project.yml"
  task :gen do
    sh XCODEGEN, "generate", "--spec", File.join(APP_DIR, "project.yml")
  end

  desc "Run the Swift Testing suites of app/Core"
  task :test do
    sh SWIFT, "test", "--package-path", CORE_DIR
  end

  desc "Build build/app/stage/ThermalPrinter.app with the bundled picoruby, dylib and CLI sources, signed with a bundle-id requirement"
  task :build => :gen do
    abort "#{APP_VM} not found - run `rake vm:build` first" unless File.exist?(APP_VM)
    abort "#{APP_BLE_DYLIB} not found - run `rake vm:build` first" unless File.exist?(APP_BLE_DYLIB)

    sh APP_XCODEBUILD, "-project", File.join(APP_DIR, "ThermalPrinter.xcodeproj"),
       "-scheme", "ThermalPrinter", "-configuration", "Release",
       "-derivedDataPath", APP_DERIVED, "CODE_SIGNING_ALLOWED=NO", "build"

    rm_rf File.dirname(APP_STAGE)
    mkdir_p File.dirname(APP_STAGE)
    sh "/usr/bin/ditto", APP_PRODUCT, APP_STAGE

    macos      = File.join(APP_STAGE, "Contents", "MacOS")
    frameworks = File.join(APP_STAGE, "Contents", "Frameworks")
    cli        = File.join(APP_STAGE, "Contents", "Resources", "cli")
    vm         = File.join(macos, "picoruby")
    dylib      = File.join(frameworks, File.basename(APP_BLE_DYLIB))
    mkdir_p frameworks
    mkdir_p cli
    cp APP_VM, vm
    cp APP_BLE_DYLIB, dylib
    cp APP_CLI_SOURCES, cli

    sh "/usr/bin/install_name_tool", "-delete_rpath", File.dirname(APP_BLE_DYLIB), vm
    sh "/usr/bin/install_name_tool", "-add_rpath", "@executable_path/../Frameworks", vm

    sh "/usr/bin/codesign", "--force", "-s", "-", dylib
    sh "/usr/bin/codesign", "--force", "-s", "-", vm
    sh "/usr/bin/codesign", "--force", "-s", "-", "-r=designated => identifier \"#{APP_BUNDLE_ID}\"", APP_STAGE
  end

  desc "Run the XCUITest suites against the Debug app with a fake CLI (never touches the printer)"
  task :uitest => :gen do
    xcodebuild_test("-skip-testing:ThermalPrinterUITests/DeviceScenarioTests")
  end

  namespace :uitest do
    desc "Fetch the card of GITHUB_URL through the real gh, preview it with the real CLI dry-run and hand one job to a fake CLI (GITHUB_URL=url GITHUB_EXPECT_ROW=text; never touches the printer)"
    task :github => :gen do
      url = ENV["GITHUB_URL"].to_s
      expect = ENV["GITHUB_EXPECT_ROW"].to_s
      abort "set GITHUB_URL to the issue or pull request URL" if url.empty?
      abort "set GITHUB_EXPECT_ROW to text the fetched card's part row must contain" if expect.empty?
      xcodebuild_test(
        "-only-testing:ThermalPrinterUITests/GitHubCardTests",
        "TEST_RUNNER_RUN_GITHUB" => "1",
        "TEST_RUNNER_GITHUB_URL" => url,
        "TEST_RUNNER_GITHUB_EXPECT_ROW" => expect
      )
    end

    desc "Print DEVICE_IMAGE on the real printer through the staged app (DEVICE_OK=1 DEVICE_IMAGE=path)"
    task :device => :gen do
      abort "refusing to print: set DEVICE_OK=1 to confirm the printer is ready" unless ENV["DEVICE_OK"] == "1"
      image = ENV["DEVICE_IMAGE"].to_s
      abort "set DEVICE_IMAGE to the image to print" if image.empty?
      abort "cannot read DEVICE_IMAGE=#{image}" unless File.file?(image) && File.readable?(image)
      abort "#{APP_STAGE} not found - run `rake app:build` first" unless File.directory?(APP_STAGE)
      abort "#{APP_STAGE} has no bundled picoruby - run `rake app:build` first" unless File.executable?(File.join(APP_STAGE, "Contents", "MacOS", "picoruby"))

      device_dir = File.join(APP_DERIVED, "device")
      rm_rf device_dir
      mkdir_p device_dir
      copy   = File.join(device_dir, "photo#{File.extname(image).downcase}")
      report = File.join(device_dir, "report.txt")
      cp image, copy

      xcodebuild_test(
        "-only-testing:ThermalPrinterUITests/DeviceScenarioTests/testPrintsThePhotoThroughTheStagedApp",
        "TEST_RUNNER_RUN_DEVICE" => "1",
        "TEST_RUNNER_DEVICE_IMAGE" => copy,
        "TEST_RUNNER_DEVICE_APP" => APP_STAGE,
        "TEST_RUNNER_DEVICE_REPORT" => report,
        "TEST_RUNNER_THERMALPRINTER_CLI" => nil
      )
      puts File.read(report) if File.exist?(report)
    end

    desc "Print the GitHub card of DEVICE_URL on the real printer through the staged app (DEVICE_OK=1 DEVICE_URL=url DEVICE_EXPECT_ROW=text)"
    task :device_card => :gen do
      abort "refusing to print: set DEVICE_OK=1 to confirm the printer is ready" unless ENV["DEVICE_OK"] == "1"
      url = ENV["DEVICE_URL"].to_s
      expect = ENV["DEVICE_EXPECT_ROW"].to_s
      abort "set DEVICE_URL to the issue or pull request URL" if url.empty?
      abort "set DEVICE_EXPECT_ROW to text the fetched card's part row must contain" if expect.empty?
      abort "#{APP_STAGE} not found - run `rake app:build` first" unless File.directory?(APP_STAGE)
      abort "#{APP_STAGE} has no bundled picoruby - run `rake app:build` first" unless File.executable?(File.join(APP_STAGE, "Contents", "MacOS", "picoruby"))

      device_dir = File.join(APP_DERIVED, "device")
      rm_rf device_dir
      mkdir_p device_dir
      report = File.join(device_dir, "report.txt")

      xcodebuild_test(
        "-only-testing:ThermalPrinterUITests/DeviceScenarioTests/testPrintsTheGitHubCardThroughTheStagedApp",
        "TEST_RUNNER_RUN_DEVICE" => "1",
        "TEST_RUNNER_DEVICE_URL" => url,
        "TEST_RUNNER_DEVICE_EXPECT_ROW" => expect,
        "TEST_RUNNER_DEVICE_APP" => APP_STAGE,
        "TEST_RUNNER_DEVICE_REPORT" => report,
        "TEST_RUNNER_THERMALPRINTER_CLI" => nil
      )
      puts File.read(report) if File.exist?(report)
    end
  end

  def xcodebuild_test(selector, env = {})
    result_bundle = File.join(UITEST_DERIVED, "last.xcresult")
    rm_rf result_bundle
    sh env, APP_XCODEBUILD, "test",
       "-project", File.join(APP_DIR, "ThermalPrinter.xcodeproj"),
       "-scheme", "ThermalPrinter",
       "-destination", "platform=macOS",
       "-derivedDataPath", UITEST_DERIVED,
       "-resultBundlePath", result_bundle,
       selector
  end

  desc "Install the built app to ~/Applications/ThermalPrinter.app"
  task :install => :build do
    mkdir_p File.dirname(APP_INSTALLED)
    rm_rf APP_INSTALLED
    sh "/usr/bin/ditto", APP_STAGE, APP_INSTALLED
  end
end
