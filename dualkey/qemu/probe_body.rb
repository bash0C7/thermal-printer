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
raise "DualKeyLink is not linked" unless DualKeyLink.respond_to?(:pair) && DualKeyLink.respond_to?(:exchange_mtu) && DualKeyLink.respond_to?(:mtu) && DualKeyLink.respond_to?(:disconnect)
puts "PROBE written #{transport.written} rows #{job.rows} blocks #{job.blocks}"
puts lines
puts "DUALKEY_PROBE_OK"
