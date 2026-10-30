class LeanClock
  def initialize
    @now = 1000
  end

  def now_ms
    @now
  end

  def advance(ms)
    @now += ms
  end
end

class LeanSleeper
  def initialize(clock)
    @clock = clock
  end

  def sleep_ms(ms)
    @clock.advance(ms)
  end
end

class LeanTransport
  REPLIES = {
    0x11 => "\x1a\x06\x89",
    0x12 => "\x1a\x05\x98",
    0x08 => "\x1a\x04\x53",
    0x13 => "\x1a\x03\xa8"
  }

  attr_reader :written

  def initialize
    @written = 0
    @queue = ["\x01\x01", "\x02\xb6\x00", "\x1a\x3b\x04\x40\x00\x00\x00"]
    @job = false
  end

  def connect(name_prefix, timeout_ms)
    true
  end

  def gatt_report
    {"service" => true, "write" => true, "notify" => true}
  end

  def subscribe(settle_ms)
    true
  end

  def write_chunk(bytes)
    @written += bytes.bytesize
    @job = true if bytes.getbyte(0) == 0x1b && bytes.getbyte(1) == 0x40
    if !@job && bytes.getbyte(0) == 0x1f
      reply = REPLIES[bytes.getbyte(2)]
      @queue << reply if reply
    end
    @queue << "\x01\x01"
  end

  def poll_notifications
    out = @queue
    @queue = []
    out
  end

  def disconnect
    nil
  end
end
