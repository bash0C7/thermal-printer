MRuby::CrossBuild.new('esp32-picoruby') do |conf|
  conf.toolchain('gcc')

  conf.cc.command = "xtensa-#{ENV['CONFIG_IDF_TARGET']}-elf-gcc"
  conf.linker.command = "xtensa-#{ENV['CONFIG_IDF_TARGET']}-elf-ld"
  conf.archiver.command = "xtensa-#{ENV['CONFIG_IDF_TARGET']}-elf-ar"

  conf.cc.host_command = 'gcc'
  conf.cc.flags << '-Wall'
  conf.cc.flags << '-Wno-format'
  conf.cc.flags << '-Wno-unused-function'
  conf.cc.flags << '-Wno-maybe-uninitialized'
  conf.cc.flags << '-mlongcalls'

  conf.cc.defines << 'MRB_TICK_UNIT=10'
  conf.cc.defines << 'MRB_TIMESLICE_TICK_COUNT=1'
  conf.cc.defines << 'MRBC_CONVERT_CRLF=1'
  conf.cc.defines << 'MRB_UTF8_STRING'
  conf.cc.defines << 'MRB_INT64'
  conf.cc.defines << 'MRB_NO_BOXING'
  conf.cc.defines << 'MRB_32BIT'
  conf.cc.defines << 'PICORB_ALLOC_ESTALLOC'
  conf.cc.defines << 'PICORB_ALLOC_ALIGN=8'
  conf.cc.defines << 'USE_FAT_FLASH_DISK'
  conf.cc.defines << 'NDEBUG'
  conf.cc.defines << "PICORB_PLATFORM_ESP32"
  conf.cc.defines << "MRC_PRISM_ARENA_BLOCK=2048"
  conf.cc.defines << "USE_WIFI" if ENV['USE_WIFI']

  if ENV['PICORB_DEBUG']
    conf.cc.defines << 'ESTALLOC_DEBUG'
    conf.enable_debug
  end

  conf.picoruby
  conf.gembox 'minimum'
  conf.gembox 'core'
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-kernel-ext"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-string-ext"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-array-ext"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-objectspace"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-metaprog"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-error"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-sprintf"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-math"
  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/R2P2-ESP32/components/picoruby-esp32/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-pack"
  conf.gem core: 'picoruby-esp32'
  conf.gem core: "picoruby-shell"
  conf.gem core: "picoruby-picoline"

  conf.gem core: 'picoruby-rng'
  conf.gem core: 'picoruby-yaml'

  conf.gem core: 'picoruby-gpio'
  conf.gem core: 'picoruby-irq'

  if ENV['USE_BLE']
    conf.gem core: 'picoruby-ble'
  end

  conf.gem core: 'picoruby-rmt'
  conf.gem core: 'picoruby-mbedtls'

  conf.gem gemdir: "#{ENV.fetch('THERMAL_PRINTER_ROOT')}/vendor/picoruby-phomemo-thermal-printer"
  conf.gem core: "picoruby-vram"
  conf.gem core: "picoruby-bdffont"
  conf.gem core: "picoruby-terminus"
  conf.gem gemdir: "#{ENV.fetch("THERMAL_PRINTER_ROOT")}/../picoruby-debug-probe"
  conf.gem gemdir: "#{ENV.fetch("THERMAL_PRINTER_ROOT")}/../picoruby-text-canvas"
  conf.gem gemdir: "#{ENV.fetch("THERMAL_PRINTER_ROOT")}/dualkey/mrbgems/dualkey-pairing"
end
