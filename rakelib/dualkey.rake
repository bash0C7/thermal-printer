require "digest"
require "open3"
require_relative "../tools/dualkey/qemu_verdict"

DK_ROOT = File.join(ROOT, "dualkey")
DK_VENDOR = File.join(ROOT, "vendor", "R2P2-ESP32")
DK_SOURCE_REPO = ENV["R2P2_ESP32_SOURCE"] || File.expand_path("~/dev/src/github.com/bash0C7/R2P2-ESP32")
DK_BUILD_CONFIG = File.join(DK_ROOT, "build_config", "esp32-dualkey-report.rb")
DK_APP = File.join(DK_ROOT, "app.rb")
DK_PROBE_BODY = File.join(DK_ROOT, "qemu", "probe_body.rb")
DK_LEAN_TRANSPORT = File.join(DK_ROOT, "qemu", "lean_transport.rb")
DK_ESP_IDF_EXPORT = ENV["ESP_IDF_EXPORT"] || File.expand_path("~/esp/esp-idf/export.sh")
DK_SMALL_FRAGMENT = File.join(DK_ROOT, "build_config", "dualkey_small.sdkconfig")
DK_HEAP_KB = Integer(ENV.fetch("DK_HEAP_KB", "190"))
DK_BOARD_HEAP_KB = Integer(ENV.fetch("DK_BOARD_HEAP_KB", "206"))
DK_SDKCONFIG_DEFAULTS = "sdkconfig.defaults;sdkconfigs/usb_console;sdkconfigs/bt_nimble;#{DK_SMALL_FRAGMENT}"
DK_QEMU_SDKCONFIG_DEFAULTS = "sdkconfig.defaults;sdkconfigs/bt_nimble;#{DK_SMALL_FRAGMENT};sdkconfigs/qemu"
DK_STORAGE_OFFSET = 0x210000
DK_STORAGE_SIZE = 0x100000
DK_FLASH_SIZE = "4MB"
DK_QEMU_VERSION = "esp_develop_9.2.2_20250817"
DK_QEMU_TARBALL = "qemu-xtensa-softmmu-#{DK_QEMU_VERSION}-aarch64-apple-darwin.tar.xz"
DK_QEMU_URL = "https://github.com/espressif/qemu/releases/download/esp-develop-9.2.2-20250817/#{DK_QEMU_TARBALL}"
DK_QEMU_SHA256 = "aa92e337461d482f5d9f31cd8efc0bd67b3de8fcfcfb567289cb43a59c184651"
DK_QEMU_DIR = File.join(ROOT, "build", "dualkey", "qemu")
DK_QEMU_BIN = File.join(DK_QEMU_DIR, DK_QEMU_VERSION, "qemu", "bin", "qemu-system-xtensa")
DK_RUN_DIR = File.join(ROOT, "build", "dualkey", "run")
DK_LOG_DIR = File.join(ROOT, "build", "dualkey", "logs")
DK_MRBC = File.join(DK_VENDOR, "components", "picoruby-esp32", "picoruby", "bin", "mrbc")
DK_HARNESS = ENV["R2P2_DEV_HARNESS"] || File.expand_path("~/dev/src/github.com/bash0C7/R2P2-dev-harness")
DK_APP_HOLD_S = 45
DK_GATE_STAMP = File.join(ROOT, "build", "dualkey", "gate.pass")

def dk_idf(cmd, heap_kb = DK_HEAP_KB)
  env = %(THERMAL_PRINTER_ROOT="#{ROOT}" R2P2_BUILD_CONFIG="#{DK_BUILD_CONFIG}" USE_BLE=1 PICORB_TASK_STACK_SIZE=16384 HEAP_SIZE=#{heap_kb * 1024})
  sh %(bash -c '. #{DK_ESP_IDF_EXPORT} && export #{env} && cd #{DK_VENDOR} && #{cmd}')
end

def dk_clean_picoruby_build
  rm_rf File.join(DK_VENDOR, "components", "picoruby-esp32", "picoruby", "build", "esp32-picoruby")
end

def dk_compile_mrb(source, out)
  abort "#{DK_MRBC} not found - run `rake dualkey:qemu_check` or `rake dualkey:build` first" unless File.executable?(DK_MRBC)
  mkdir_p File.dirname(out)
  rm_f out
  sh DK_MRBC, "-o", out, source
  out
end

def dk_qemu_run(flash:, efuse:, log:, decide:, timeout: 900)
  argv = [
    DK_QEMU_BIN, "-M", "esp32s3", "-m", "8M",
    "-drive", "file=#{flash},if=mtd,format=raw",
    "-drive", "file=#{efuse},if=none,format=raw,id=efuse",
    "-global", "driver=nvram.esp32s3.efuse,property=drive,value=efuse",
    "-global", "driver=timer.esp32s3.timg,property=wdt_disable,value=true",
    "-display", "none", "-serial", "file:#{log}", "-monitor", "none",
    "-icount", "shift=2,align=off,sleep=off", "-seed", "1", "-rtc", "clock=vm"
  ]
  rm_f log
  stderr_log = "#{log}.stderr"
  pid = Process.spawn(*argv, out: File::NULL, err: stderr_log)
  started = Time.now
  deadline = started + timeout
  loop do
    verdict = decide.call(File.exist?(log) ? File.binread(log) : "", (Time.now - started).to_i)
    return verdict if verdict.decided
    _, status = Process.wait2(pid, Process::WNOHANG)
    if status
      pid = nil
      return DualkeyQemu::Verdict.new(false, "qemu exited (#{status}) before a verdict: #{File.read(stderr_log).strip}", true)
    end
    return DualkeyQemu::Verdict.new(false, "#{verdict.message} within #{timeout} s", true) if Time.now >= deadline
    sleep 1
  end
ensure
  if pid
    Process.kill("TERM", pid)
    Process.wait(pid)
  end
end

def dk_storage_image(app_mrb, out_bin)
  storage = File.join(DK_RUN_DIR, "storage")
  rm_rf storage
  mkdir_p File.join(storage, "home")
  cp app_mrb, File.join(storage, "home", "app.mrb")
  littlefs = Dir.glob(File.join(DK_VENDOR, "build-qemu", "**", "littlefs-python")).find { |p| File.executable?(p) }
  abort "littlefs-python not found under build-qemu" unless littlefs
  rm_f out_bin
  sh littlefs, "create", "--fs-size=#{DK_STORAGE_SIZE}", "--name-max=64", "--block-size=4096", storage, out_bin
end

def dk_flash_image(out_bin, storage_bin)
  rm_f out_bin
  sh %(bash -c '. #{DK_ESP_IDF_EXPORT} && cd #{File.join(DK_VENDOR, "build-qemu")} && esptool.py --chip esp32s3 merge_bin -o #{out_bin} --fill-flash-size #{DK_FLASH_SIZE} @flash_args')
  image = File.binread(storage_bin)
  abort "storage image is #{image.bytesize} bytes, partition is #{DK_STORAGE_SIZE}" unless image.bytesize == DK_STORAGE_SIZE
  File.open(out_bin, "r+b") { |io| io.seek(DK_STORAGE_OFFSET); io.write(image) }
end

def dk_efuse_image(path)
  bytes = Array.new(1024, 0)
  bytes[37] = 0x0c
  bytes[64] = 0x01
  File.binwrite(path, bytes.pack("C*"))
end

namespace :dualkey do
  desc "Copy R2P2-ESP32 (BLE lineage) into vendor/ with an APFS clone and let the build config come from outside"
  task :setup do
    abort "#{DK_SOURCE_REPO} not found (set R2P2_ESP32_SOURCE)" unless Dir.exist?(DK_SOURCE_REPO)
    unless Dir.exist?(DK_VENDOR)
      mkdir_p DK_VENDOR
      Dir.children(DK_SOURCE_REPO).each do |name|
        next if name.start_with?("build") || name.start_with?("qemu-") || name == "sdkconfig" || name == "sdkconfig.old"
        sh "cp", "-c", "-R", File.join(DK_SOURCE_REPO, name), File.join(DK_VENDOR, name)
      end
    end
    cmake = File.join(DK_VENDOR, "components", "picoruby-esp32", "CMakeLists.txt")
    text = File.read(cmake)
    unless text.include?("R2P2_BUILD_CONFIG")
      anchor = "if(CONFIG_ESP_WIFI_ENABLED AND DEFINED ENV{USE_WIFI})"
      abort "anchor not found in #{cmake}" unless text.include?(anchor)
      patch = "if(DEFINED ENV{R2P2_BUILD_CONFIG})\n  set(MRUBY_CONFIG_STRING \"$ENV{R2P2_BUILD_CONFIG}\")\nendif()\n\n"
      File.write(cmake, text.sub(anchor, "#{patch}#{anchor}"))
    end
    cp File.join(DK_ROOT, "firmware", "main_task.rb"), File.join(DK_VENDOR, "components", "picoruby-esp32", "mrblib", "main_task.rb")
    mkdir_p File.join(ROOT, "build")
    File.write(File.join(ROOT, "build", "dualkey-r2p2-esp32.commit"),
               "#{`git -C #{DK_SOURCE_REPO} rev-parse HEAD`.strip}\n" \
               "#{`git -C #{File.join(DK_SOURCE_REPO, "components", "picoruby-esp32", "picoruby")} rev-parse HEAD`.strip}\n")
    puts "[dualkey] #{DK_VENDOR} ready"
  end

  desc "Download the pinned QEMU for Apple Silicon into build/dualkey/qemu"
  task :qemu_setup do
    next puts("[dualkey] #{DK_QEMU_BIN} present") if File.executable?(DK_QEMU_BIN)
    mkdir_p DK_QEMU_DIR
    tarball = File.join(DK_QEMU_DIR, DK_QEMU_TARBALL)
    sh "curl", "-L", "--fail", "-o", tarball, DK_QEMU_URL unless File.exist?(tarball)
    actual = Digest::SHA256.file(tarball).hexdigest
    abort "sha256 #{actual} does not match #{DK_QEMU_SHA256}" unless actual == DK_QEMU_SHA256
    mkdir_p File.join(DK_QEMU_DIR, DK_QEMU_VERSION)
    sh "tar", "-xJf", tarball, "-C", File.join(DK_QEMU_DIR, DK_QEMU_VERSION)
    out, err, status = Open3.capture3(DK_QEMU_BIN, "--version")
    abort "qemu --version failed:\n#{err}" unless status.success? && out.include?(DK_QEMU_VERSION)
    puts out.lines.first
  end

  desc "Build the firmware for the board (gems: phomemo printer + device report)"
  task build: :setup do
    dk_clean_picoruby_build
    dk_idf %(rm -f sdkconfig && SDKCONFIG_DEFAULTS="#{DK_SDKCONFIG_DEFAULTS}" idf.py set-target esp32s3), DK_BOARD_HEAP_KB
    dk_idf %(SDKCONFIG_DEFAULTS="#{DK_SDKCONFIG_DEFAULTS}" idf.py -DPICORB_VM=mruby build), DK_BOARD_HEAP_KB
    header = File.join(DK_VENDOR, "build", "config", "sdkconfig.h")
    abort "#{header} lacks the USB console" unless File.read(header).include?("#define CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG 1")
  end

  desc "Boot the firmware under QEMU: run the print path with a fake transport, then run app.rb itself"
  task qemu_check: %i[setup qemu_setup] do
    dk_clean_picoruby_build
    rm_rf File.join(DK_VENDOR, "build-qemu")
    qemu_env = %(SDKCONFIG_DEFAULTS="#{DK_QEMU_SDKCONFIG_DEFAULTS}" idf.py -B build-qemu -DSDKCONFIG=build-qemu/sdkconfig)
    dk_idf "#{qemu_env} set-target esp32s3"
    dk_idf "#{qemu_env} -DPICORB_VM=mruby build"

    mkdir_p DK_RUN_DIR
    mkdir_p DK_LOG_DIR
    efuse = File.join(DK_RUN_DIR, "efuse.bin")
    dk_efuse_image(efuse)
    stamp = Time.now.strftime("%Y%m%d-%H%M%S")

    probe_rb = File.join(DK_RUN_DIR, "probe.rb")
    File.write(probe_rb, [File.read(DK_LEAN_TRANSPORT), File.read(DK_PROBE_BODY)].join("\n"))
    runs = {
      "probe" => [probe_rb, ->(log, _t) { DualkeyQemu.probe(log) }],
      "app" => [DK_APP, dk_app_decider]
    }
    failed = false
    runs.each do |name, (source, decide)|
      mrb = dk_compile_mrb(source, File.join(DK_RUN_DIR, "#{name}.mrb"))
      storage = File.join(DK_RUN_DIR, "storage-#{name}.bin")
      dk_storage_image(mrb, storage)
      flash = File.join(DK_RUN_DIR, "flash-#{name}.bin")
      dk_flash_image(flash, storage)
      log = File.join(DK_LOG_DIR, "qemu-#{name}-#{stamp}.log")
      verdict = dk_qemu_run(flash: flash, efuse: efuse, log: log, decide: decide)
      puts "[dualkey:qemu_check] #{name} #{verdict.pass ? "PASS" : "FAIL"} - #{verdict.message} - log: #{log}"
      failed ||= !verdict.pass
    end
    abort "[dualkey:qemu_check] FAIL" if failed
    File.write(DK_GATE_STAMP, dk_tree_digest)
  end

end

namespace :dualkey do
  desc "Run FILE=<script.rb> as /home/app.mrb under QEMU on the existing build-qemu and print the log (SECONDS=60)"
  task :qemu_run do
    source = File.expand_path(ENV.fetch("FILE"))
    seconds = Integer(ENV.fetch("SECONDS", "60"))
    mkdir_p DK_RUN_DIR
    mkdir_p DK_LOG_DIR
    efuse = File.join(DK_RUN_DIR, "efuse.bin")
    dk_efuse_image(efuse)
    mrb = dk_compile_mrb(source, File.join(DK_RUN_DIR, "run.mrb"))
    storage = File.join(DK_RUN_DIR, "storage-run.bin")
    dk_storage_image(mrb, storage)
    flash = File.join(DK_RUN_DIR, "flash-run.bin")
    dk_flash_image(flash, storage)
    log = File.join(DK_LOG_DIR, "qemu-run-#{Time.now.strftime("%H%M%S")}.log")
    decide = lambda do |text, elapsed|
      loaded = text.index("Loading app.mrb")
      done = (loaded && text.index("$> ", loaded)) || elapsed >= seconds
      DualkeyQemu::Verdict.new(false, "running", done)
    end
    dk_qemu_run(flash: flash, efuse: efuse, log: log, decide: decide, timeout: seconds + 900)
    puts File.binread(log).sub(/\A.*?Loading app\.mrb/m, "Loading app.mrb")
  end
end

namespace :dualkey do
  desc "Build only the QEMU variant (no run)"
  task qemu_build: %i[setup qemu_setup] do
    dk_clean_picoruby_build
    rm_rf File.join(DK_VENDOR, "build-qemu")
    qemu_env = %(SDKCONFIG_DEFAULTS="#{DK_QEMU_SDKCONFIG_DEFAULTS}" idf.py -B build-qemu -DSDKCONFIG=build-qemu/sdkconfig)
    dk_idf "#{qemu_env} set-target esp32s3"
    dk_idf "#{qemu_env} -DPICORB_VM=mruby build"
  end
end

def dk_app_decider
  seen = nil
  lambda do |log, t|
    seen = t if seen.nil? && log.include?(DualkeyQemu::APP_LOADED)
    DualkeyQemu.app(log, elapsed_s: seen ? t - seen : 0, hold_s: DK_APP_HOLD_S)
  end
end

DK_BOARD_PRODUCT = "USB JTAG/serial debug unit"
DK_PICOMODEM_GEMFILE = File.join(DK_ROOT, "Gemfile")

def dk_board_port
  ports = `ioreg -w 0 -r -n "#{DK_BOARD_PRODUCT}" -l 2>/dev/null`.scan(/"IOCalloutDevice" = "([^"]+)"/).flatten.sort
  abort "[dualkey] no ESP32-S3 board on USB" if ports.empty?
  abort "[dualkey] #{ports.size} ESP32-S3 boards on USB (#{ports.join(", ")}); name one with ESPPORT=" if ports.size > 1 && ENV["ESPPORT"].to_s.empty?
  port = ENV["ESPPORT"].to_s.empty? ? ports.first : ENV["ESPPORT"]
  abort "[dualkey] ESPPORT=#{port} is not among #{ports.join(", ")}" unless ports.include?(port)
  port
end

def dk_esptool(port, *args)
  sh %(bash -c '. #{DK_ESP_IDF_EXPORT} && python -m esptool --chip esp32s3 -p #{port} #{args.join(" ")}')
end

def dk_assert_dualkey(port)
  out, status = Open3.capture2e(%(bash -c '. #{DK_ESP_IDF_EXPORT} >/dev/null 2>&1 && python -m esptool --chip esp32s3 -p #{port} chip_id'))
  abort "[dualkey] chip_id failed:\n#{out}" unless status.success?
  features = out[/Features:.*/].to_s
  abort "[dualkey] #{port} reports #{features.inspect}; the DualKey has no PSRAM" if features.include?("PSRAM")
  puts "[dualkey] #{port}: #{features}"
end

namespace :dualkey do
  desc "Flash the firmware after the QEMU gate and a clean board build (ESPPORT= optional)"
  task flash: :build do
    dk_require_gate_stamp
    port = dk_board_port
    dk_assert_dualkey(port)
    dk_idf "ESPPORT=#{port} idf.py flash", DK_BOARD_HEAP_KB
  end

  desc "Erase the storage partition (removes /home/app.mrb) so the shell is reachable again"
  task :wipe do
    port = dk_board_port
    dk_assert_dualkey(port)
    dk_esptool port, "erase_region", format("0x%x", DK_STORAGE_OFFSET), format("0x%x", DK_STORAGE_SIZE)
  end

  desc "Compile dualkey/app.rb with the firmware mrbc, wipe storage, and transfer it as /home/app.mrb over PicoModem"
  task :deploy_app do
    port = dk_board_port
    dk_assert_dualkey(port)
    mrb = dk_compile_mrb(ENV["APP"] ? File.expand_path(ENV["APP"]) : DK_APP, File.join(DK_RUN_DIR, "app.mrb"))
    Rake::Task["dualkey:wipe"].invoke
    pmput = File.join(DK_HARNESS, "tools", "esp32", "pmput.rb")
    sh({"BUNDLE_GEMFILE" => DK_PICOMODEM_GEMFILE}, "bundle", "exec", RbConfig.ruby, pmput, mrb, "/home/app.mrb", port)
  end
end

def dk_tree_digest
  files = Dir[File.join(DK_ROOT, "firmware", "*"), File.join(DK_ROOT, "build_config", "*"),
              File.join(ROOT, "..", "picoruby-debug-probe", "mrblib", "**", "*.rb"),
              File.join(ROOT, "..", "picoruby-text-canvas", "mrblib", "**", "*.rb"),
              File.join(GEM_DIR, "mrblib", "**", "*.rb")].select { |f| File.file?(f) }.sort
  Digest::SHA256.hexdigest(files.map { |f| "#{f}\n#{File.binread(f)}" }.join("\0"))
end

def dk_require_gate_stamp
  stamp = File.exist?(DK_GATE_STAMP) ? File.read(DK_GATE_STAMP) : nil
  abort "[dualkey] no QEMU gate pass for this tree - run `rake dualkey:qemu_check` first" unless stamp == dk_tree_digest
end

namespace :dualkey do
  desc "Record the current tree as gate-passed from build/dualkey/logs/qemu_check.out (exit=0 and both runs PASS)"
  task :gate_stamp do
    out = File.read(File.join(DK_LOG_DIR, "qemu_check.out"))
    ok = out.include?("probe PASS") && out.include?("app PASS") && out.match?(/^exit=0$/)
    abort "[dualkey] qemu_check.out does not show a full pass" unless ok
    File.write(DK_GATE_STAMP, dk_tree_digest)
  end
end
