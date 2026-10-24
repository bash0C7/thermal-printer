PRODUCT_BUILD_DIR = File.join(RD, "build")
TEST_BUILD_DIR    = File.join(ROOT, "build", "picotest")

def openssl_env
  ssl = `brew --prefix openssl@3 2>/dev/null`.strip
  return {} if ssl.empty?
  { "LDFLAGS" => [ENV["LDFLAGS"], "-L#{ssl}/lib"].compact.join(" "),
    "CFLAGS"  => [ENV["CFLAGS"],  "-I#{ssl}/include"].compact.join(" ") }
end

def vm_build(config, build_dir)
  abort "#{PICORUBY_SRC} not found - run `rake vendor:setup` first" unless Dir.exist?(PICORUBY_SRC)
  sh({ "MRUBY_BUILD_DIR" => build_dir,
       "MRUBY_CONFIG"    => File.expand_path(config, ROOT) }.merge(openssl_env),
     "rake", "-C", PICORUBY_SRC)
end

namespace :vm do
  desc "Build picoruby with build_config/darwin-thermal-printer.rb into vendor/R2P2-darwin/build"
  task :build do
    vm_build("build_config/darwin-thermal-printer.rb", PRODUCT_BUILD_DIR)
  end

  desc "Remove the built product VM and test VM"
  task :clean do
    rm_rf File.join(PRODUCT_BUILD_DIR, "host")
    rm_rf TEST_BUILD_DIR
  end
end

namespace :picotest do
  desc "Build the BLE-less test VM (build_config/picoruby-test.rb) into build/picotest"
  task :build do
    vm_build("build_config/picoruby-test.rb", TEST_BUILD_DIR)
  end

  task :ensure_vm do
    Rake::Task["picotest:build"].invoke unless File.executable?(TEST_VM)
  end
end
