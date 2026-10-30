require 'gpio'
require 'rmt'
require 'ble'
require 'phomemo_thermal_printer'
require 'debug_probe'
require 'text_canvas'

class Clock
  def now_ms
    Machine.board_millis
  end
end

class Sleeper
  def sleep_ms(ms)
    Kernel.sleep_ms(ms)
  end
end

class LinkTransport < PhomemoThermalPrinter::Transport
  PAIR_WAIT_MS = 3000
  MTU_WAIT_MS = 500
  DISCONNECT_WAIT_MS = 500

  def subscribe(settle_ms)
    pair_rc = DualKeyLink.pair(@handle)
    sleep_ms(PAIR_WAIT_MS) if pair_rc == 0
    mtu_rc = DualKeyLink.exchange_mtu(@handle)
    sleep_ms(MTU_WAIT_MS) if mtu_rc == 0
    super
  end

  def disconnect
    if @handle
      DualKeyLink.disconnect(@handle)
      sleep_ms(DISCONNECT_WAIT_MS)
    end
    super
  end
end

class Key
  def initialize(pin)
    @gpio = GPIO.new(pin, GPIO::IN | GPIO::PULL_UP)
  end

  def pressed?
    @gpio.read == 0
  end
end

class Led
  PIXELS = 2

  def initialize(pin, power_pin)
    @power = GPIO.new(power_pin, GPIO::OUT)
    @power.write(1)
    sleep_ms(10)
    @rmt = RMT.new(pin, t0h_ns: 350, t0l_ns: 800, t1h_ns: 700, t1l_ns: 600, reset_ns: 60000)
  end

  def fill(rgb)
    bytes = []
    i = 0
    while i < PIXELS
      bytes << rgb[1] << rgb[0] << rgb[2]
      i += 1
    end
    @rmt.write(bytes)
  end
end

RED = [255, 0, 0]
BLUE = [0, 0, 255]
IDLE = [0, 32, 0]

clock = Clock.new
sleeper = Sleeper.new
transport = nil
led = Led.new(21, 40)
key1 = Key.new(17)
key2 = Key.new(0)
outcome = nil

print_lines = lambda do |lines|
  job = PhomemoThermalPrinter::Job.new(TextCanvas.new([""] + lines + ["", ""]), density: 4, feed: 3)
  transport = LinkTransport.new if transport.nil?
  session = PhomemoThermalPrinter::PrintSession.new(transport, clock: clock, sleeper: sleeper)
  session.run(job)
end

probe = DebugProbe.new
probe.gauge("LAST PRINT") { outcome }
probe.gauge("TASKS") { Task.list.size }
probe.watch(:key1) { key1.pressed? }
probe.watch(:key2) { key2.pressed? }

lit_print = lambda do |name, color, snap|
  led.fill(color)
  puts snap.to_lines.join(" | ")
  begin
    result = print_lines.call(snap.to_lines)
    outcome = result.ok ? "OK" : result.error.to_s.upcase
    puts "PRINT #{name} #{outcome}"
  rescue Exception => e
    outcome = "RAISED #{e.class}"
    puts "PRINT #{name} #{outcome} #{e.message}"
  ensure
    transport.disconnect if transport
    GC.start
    probe.sample
    led.fill(IDLE)
  end
end

probe.on(:key1) { |snap| lit_print.call("key1", RED, snap) }
probe.on(:key2) { |snap| lit_print.call("key2", BLUE, snap) }
probe.on(:error) { |e| puts "ERROR #{e.class} #{e.message}" }

led.fill(IDLE)
while true
  probe.poll
  sleep_ms 10
end
