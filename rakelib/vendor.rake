R2P2_DARWIN_REPO = ENV["R2P2_DARWIN_REPO"] || "https://github.com/bash0C7/R2P2-darwin.git"
R2P2_DARWIN_REF  = ENV["R2P2_DARWIN_REF"]  || "main"
PORT_DARWIN_COMMIT_FILE = File.join(ROOT, "build", "port-darwin.commit")

def record_port_darwin_commit
  sha = `git -C #{PICORUBY_SRC} rev-parse HEAD`.strip
  abort "could not read the picoruby commit in #{PICORUBY_SRC}" unless sha.match?(/\A\h{40}\z/)
  mkdir_p File.dirname(PORT_DARWIN_COMMIT_FILE)
  File.write(PORT_DARWIN_COMMIT_FILE, "#{sha}\n")
  puts "[vendor] port-darwin #{sha}"
end

namespace :vendor do
  desc "Clone R2P2-darwin and fetch its picoruby (port-darwin head), then record the picoruby commit"
  task :setup do
    sh "git clone --branch #{R2P2_DARWIN_REF} #{R2P2_DARWIN_REPO} #{RD}" unless Dir.exist?(RD)
    sh "rake", "-C", RD, "setup"
    record_port_darwin_commit
  end

  desc "Re-fetch port-darwin head into vendor/picoruby, record the commit, and drop the built VMs"
  task :refresh do
    abort "#{RD} not found - run `rake vendor:setup` first" unless Dir.exist?(RD)
    sh "rake", "-C", RD, "refresh"
    record_port_darwin_commit
    Rake::Task["vm:clean"].invoke
  end
end
