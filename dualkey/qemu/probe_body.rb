def stat(label)
  s = PicoRubyVM.memory_statistics
  puts "PROBE #{label} used=#{s[:used]} free=#{s[:free]} max=#{s[:max_free]}"
end

stat("start")
transport = LeanTransport.new
clock = LeanClock.new
probe = DebugProbe.new
probe.gauge("KEY1 PRESS") { 1 }
lines = probe.snapshot.to_lines
stat("snapshot")
job = PhomemoThermalPrinter::Job.new(TextCanvas.new(lines), density: 4, feed: 3)
session = PhomemoThermalPrinter::PrintSession.new(transport, clock: clock, sleeper: LeanSleeper.new(clock))
result = session.run(job)
stat("printed")
raise "print failed: #{result.error}" unless result.ok
raise "DualKeyPairing.initiate is not linked" unless DualKeyPairing.respond_to?(:initiate)
puts "PROBE written #{transport.written} rows #{job.rows} blocks #{job.blocks}"
puts lines
puts "DUALKEY_PROBE_OK"
