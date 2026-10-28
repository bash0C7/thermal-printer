platform = ENV.fetch("IOS_SDK", "iphonesimulator")
sdk_path = `xcrun --sdk #{platform} --show-sdk-path`.strip
clang    = `xcrun --sdk #{platform} --find clang`.strip
ar       = `xcrun --sdk #{platform} --find ar`.strip
os_min   = ENV["IOS_MIN"] || "17.0"
min_flag = platform == "iphoneos" ? "-miphoneos-version-min=#{os_min}" : "-mios-simulator-version-min=#{os_min}"

module MRuby
  class Build
    def darwin?
      false
    end unless method_defined?(:darwin?)
  end
end

MRuby::CrossBuild.new(ENV.fetch("IOS_BUILD_NAME", "ios-thermal-printer-sim")) do |conf|
  conf.toolchain :clang

  conf.linker.libraries.delete("m")

  conf.cc.command       = clang
  conf.linker.command   = clang
  conf.archiver.command = ar
  conf.cc.host_command  = "clang"

  conf.cc.flags << "-arch" << "arm64"
  conf.cc.flags << "-isysroot" << sdk_path
  conf.cc.flags << min_flag

  conf.cc.defines << "MRB_TICK_UNIT=4"
  conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=3"
  conf.cc.defines << "PICORB_ALLOC_ALIGN=8"
  conf.cc.defines << "PICORB_ALLOC_ESTALLOC"
  conf.cc.defines << "PICORB_PLATFORM_POSIX"
  conf.cc.defines << "PICORB_PLATFORM_DARWIN"
  conf.cc.defines << "MRB_INT64"
  conf.cc.defines << "MRB_NO_BOXING"
  conf.cc.defines << "MRB_UTF8_STRING"

  conf.picoruby

  conf.gem core: "mruby-compiler"

  mruby_mrbgems = "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-string-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-pack"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-sprintf"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-toplevel-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-object-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-numeric-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-kernel-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-array-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-hash-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-proc-ext"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-method"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-metaprog"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-error"
  conf.gem gemdir: "#{mruby_mrbgems}/mruby-io"

  conf.ports :darwin, :posix
  conf.gem core: "picoruby-machine"
  conf.gem core: "picoruby-json"

  ble_gemdir = ENV["PICORUBY_BLE_GEMDIR"] || "#{MRUBY_ROOT}/mrbgems/picoruby-ble"
  conf.cc.include_paths << "#{ble_gemdir}/ports/darwin/ext"
  conf.gem ble_gemdir

  conf.gem gemdir: File.expand_path("../vendor/picoruby-phomemo-thermal-printer", __dir__)
end
