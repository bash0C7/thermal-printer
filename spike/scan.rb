require "env"
require "ble"

class SpikeScan < BLE
  def initialize(log, prefix)
    super(:central)
    @log = log
    @prefix = prefix
    @seen = {}
    @hits = 0
  end

  attr_reader :hits, :seen

  def advertising_report_callback(report)
    addr = BLE::Utils.bd_addr_to_str(report.address)
    return if @seen[addr]
    name = report.reports[:complete_local_name] || report.reports[:shortened_local_name] || ""
    @seen[addr] = name
    mark = name.start_with?(@prefix) ? " <== #{@prefix}" : ""
    @hits += 1 unless mark.empty?
    emit("seen #{addr} rssi=#{report.rssi} name=#{name.inspect}#{mark} keys=#{report.reports.keys.inspect}")
  end

  def emit(line)
    puts line
    f = File.open(@log, "a")
    f.puts line
    f.close
  end
end

log = ARGV[0] || "/Users/bash/dev/src/github.com/bash0C7/thermal-printer/build/logs/scan.log"
timeout_ms = (ARGV[1] || "5000").to_i
prefix = ARGV[2] || "T02"

scanner = SpikeScan.new(log, prefix)
scanner.emit("scan start argv=#{ARGV.inspect} timeout_ms=#{timeout_ms}")
scanner.scan(timeout_ms: timeout_ms, stop_state: :no_stop)
scanner.emit("scan done devices=#{scanner.seen.size} #{prefix}_hits=#{scanner.hits}")
exit(scanner.hits > 0 ? 0 : 3)
