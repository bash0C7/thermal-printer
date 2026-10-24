R2P2_DARWIN_REPO = ENV["R2P2_DARWIN_REPO"] || "https://github.com/bash0C7/R2P2-darwin.git"
R2P2_DARWIN_REF  = ENV["R2P2_DARWIN_REF"]  || "main"
GEM_REPO         = ENV["PHOMEMO_GEM_REPO"] || "https://github.com/bash0C7/picoruby-phomemo-thermal-printer.git"
GEM_REF          = ENV["PHOMEMO_GEM_REF"]  || "main"
PORT_DARWIN_COMMIT_FILE = File.join(ROOT, "build", "port-darwin.commit")
GEM_COMMIT_FILE         = File.join(ROOT, "build", "phomemo-gem.commit")

def record_commit(dir, file, label)
  sha = `git -C #{dir} rev-parse HEAD`.strip
  abort "could not read the commit in #{dir}" unless sha.match?(/\A\h{40}\z/)
  mkdir_p File.dirname(file)
  File.write(file, "#{sha}\n")
  puts "[vendor] #{label} #{sha}"
end

namespace :vendor do
  desc "Clone R2P2-darwin (with its picoruby) and the phomemo gem, then record the picoruby and gem commits"
  task :setup do
    sh "git clone --branch #{R2P2_DARWIN_REF} #{R2P2_DARWIN_REPO} #{RD}" unless Dir.exist?(RD)
    sh "git clone --branch #{GEM_REF} #{GEM_REPO} #{GEM_DIR}" unless Dir.exist?(GEM_DIR)
    sh "rake", "-C", RD, "setup"
    record_commit(PICORUBY_SRC, PORT_DARWIN_COMMIT_FILE, "port-darwin")
    record_commit(GEM_DIR, GEM_COMMIT_FILE, "phomemo gem")
  end

  desc "Re-fetch port-darwin head and the phomemo gem head, record the commits, and drop the built VMs"
  task :refresh do
    abort "#{RD} not found - run `rake vendor:setup` first" unless Dir.exist?(RD)
    abort "#{GEM_DIR} not found - run `rake vendor:setup` first" unless Dir.exist?(GEM_DIR)
    sh "rake", "-C", RD, "refresh"
    sh "git", "-C", GEM_DIR, "pull", "--ff-only"
    record_commit(PICORUBY_SRC, PORT_DARWIN_COMMIT_FILE, "port-darwin")
    record_commit(GEM_DIR, GEM_COMMIT_FILE, "phomemo gem")
    Rake::Task["vm:clean"].invoke
  end
end
