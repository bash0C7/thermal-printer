require "env"
require "ble"
require "phomemo_thermal_printer"

def hex(value)
  out = []
  i = 0
  while i < value.bytesize
    out << sprintf("%02x", value.getbyte(i))
    i += 1
  end
  out.join(" ")
end

t0 = Machine.board_millis
transport = PhomemoThermalPrinter::Darwin::Transport.new
connected = transport.connect("T02", 20000)
puts "[+#{Machine.board_millis - t0}ms] connect=#{connected.inspect}"
exit 3 unless connected

report = transport.gatt_report
puts "[+#{Machine.board_millis - t0}ms] gatt_report=#{report.inspect}"
exit 4 unless report["service"] && report["write"] && report["notify"]

subscribed = transport.subscribe(200)
puts "[+#{Machine.board_millis - t0}ms] subscribe=#{subscribed.inspect}"

resubscribed = transport.subscribe(200)
puts "[+#{Machine.board_millis - t0}ms] resubscribe=#{resubscribed.inspect}"

polls = 0
seen = 0
while polls < 100
  notes = transport.poll_notifications
  if notes.nil?
    puts "[+#{Machine.board_millis - t0}ms] poll=nil (disconnected)"
    break
  end
  i = 0
  while i < notes.size
    seen += 1
    puts "[+#{Machine.board_millis - t0}ms] notify##{seen} #{hex(notes[i])}"
    i += 1
  end
  sleep_ms(50)
  polls += 1
end
puts "[+#{Machine.board_millis - t0}ms] total notifications=#{seen}"
transport.disconnect
exit 0
