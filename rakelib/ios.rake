IOS_DIR = File.join(ROOT, "ios")

def ios_env(sdk)
  device = sdk == "iphoneos"
  { "APP_DIR"             => IOS_DIR,
    "APP_NAME"            => "thermal-printer",
    "APP_SCHEME"          => "ThermalPrinterPhone",
    "APP_BUNDLE"          => "com.bash0c7.thermalprinter.phone",
    "IOS_SDK"             => sdk,
    "IOS_BUILD_NAME"      => "ios-thermal-printer-#{device ? "device" : "sim"}",
    "MRUBY_CONFIG"        => File.join(ROOT, "build_config", "darwin-thermal-printer-ios.rb"),
    "MRUBY_CONFIG_DEVICE" => File.join(ROOT, "build_config", "darwin-thermal-printer-ios.rb") }
end

def ios_rake(task, sdk = "iphonesimulator", extra = {})
  abort "#{RD} not found - run `rake vendor:setup` first" unless Dir.exist?(RD)
  sh ios_env(sdk).merge(extra), "rake", "-C", RD, "ios:app:#{task}"
end

namespace :ios do
  desc "Cross-build libmruby.a for the Simulator with the T02 gem and stage it under ios/Vendor"
  task(:lib) { ios_rake("lib") }

  desc "Generate ios/ThermalPrinterPhone.xcodeproj"
  task(:gen) { ios_rake("gen") }

  desc "Build the iPhone app for the Simulator"
  task(:build) { ios_rake("build") }

  desc "Install and launch the iPhone app on a Simulator"
  task(:run) { ios_rake("run") }

  desc "lib -> gen -> build -> run on the Simulator"
  task(:all) { ios_rake("all") }

  desc "Launch the iPhone app N times on a frozen Simulator and require the VM to boot"
  task(:observe) { ios_rake("observe", "iphonesimulator", "APP_GOLDEN" => "[ThermalPrinterPhone] VM opened") }

  namespace :device do
    desc "Cross-build libmruby.a for iphoneos arm64 and stage it under ios/Vendor"
    task(:lib) { ios_rake("device:lib", "iphoneos") }

    desc "Link the iPhone app for a generic device without signing"
    task(:check) { ios_rake("device:check", "iphoneos") }

    desc "Build, install and launch the iPhone app on the connected device (needs a signed, unlocked iPhone)"
    task(:all) { ios_rake("device:all", "iphoneos") }
  end
end
