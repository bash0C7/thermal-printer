class FakeClock
  def initialize(start = 1000)
    @now = start
  end

  def now_ms
    @now
  end

  def advance(ms)
    @now += ms
  end
end

class FakeSleeper
  attr_reader :slept

  def initialize(clock)
    @clock = clock
    @slept = []
  end

  def sleep_ms(ms)
    @slept << ms
    @clock.advance(ms)
  end
end

class FakeTransport
  READY = {"service" => true, "write" => true, "notify" => true}
  SUBSCRIBE_NOTIFICATIONS = ["\x01\x01", "\x02\xb6\x00", "\x1a\x3b\x04\x40\x00\x00\x00"]

  attr_reader :clock, :sleeper, :writes, :subscribes, :connects, :disconnects

  def initialize(clock = FakeClock.new, found: true, gatt: READY, replies: {}, events_at_write: {},
                 completion_after_ms: 1500, completion: "\x1a\x0f\x0c", disconnect_at_write: nil,
                 connect_notifications: SUBSCRIBE_NOTIFICATIONS, notify_from_subscribe: 1,
                 disconnect_at_poll: nil, acks: true, poll_error_at_write: nil, poll_error_repeats: false,
                 poll_error_ms_after_write: nil)
    @clock = clock
    @sleeper = FakeSleeper.new(clock)
    @found = found
    @gatt = gatt
    @replies = replies
    @events_at_write = events_at_write
    @completion_after_ms = completion_after_ms
    @completion = completion
    @disconnect_at_write = disconnect_at_write
    @connect_notifications = connect_notifications
    @notify_from_subscribe = notify_from_subscribe
    @disconnect_at_poll = disconnect_at_poll
    @acks = acks
    @poll_error_at_write = poll_error_at_write
    @poll_error_repeats = poll_error_repeats
    @poll_error_raised = false
    @poll_error_ms_after_write = poll_error_ms_after_write
    @writes = []
    @subscribes = []
    @connects = []
    @disconnects = 0
    @queue = []
    @notify_on = false
    @job_started = false
    @job_start_index = nil
    @job_writes = 0
    @last_job_write_ms = nil
    @completion_sent = false
    @lost = false
    @polls = 0
  end

  def connect(name_prefix, timeout_ms)
    @connects << [name_prefix, timeout_ms]
    return true if @found
    @clock.advance(timeout_ms)
    false
  end

  def gatt_report
    @gatt
  end

  def subscribe(settle_ms)
    @subscribes << @clock.now_ms
    if @subscribes.size >= @notify_from_subscribe && !@notify_on
      @notify_on = true
      push_all(@connect_notifications)
    end
    @clock.advance(settle_ms)
    true
  end

  def write_chunk(bytes)
    if !@job_started && bytes.bytesize >= 2 && bytes.getbyte(0) == 0x1b && bytes.getbyte(1) == 0x40
      @job_started = true
      @job_start_index = @writes.size
    end
    @writes << [@clock.now_ms, bytes]
    push_all(["\x01\x01"]) if @acks && @notify_on
    if @job_started
      @job_writes += 1
      @last_job_write_ms = @clock.now_ms
      event = @events_at_write[@job_writes]
      push_all([event]) if event
      @lost = true if @disconnect_at_write == @job_writes
    elsif @notify_on
      reply = @replies[bytes]
      if reply
        push_all(reply.is_a?(Array) ? reply : [reply])
      end
    end
  end

  def poll_notifications
    @polls += 1
    return nil if @lost
    if @poll_error_at_write && @job_writes >= @poll_error_at_write && (@poll_error_repeats || !@poll_error_raised)
      @poll_error_raised = true
      raise "poll failed"
    end
    if @poll_error_ms_after_write && @last_job_write_ms && @clock.now_ms - @last_job_write_ms >= @poll_error_ms_after_write
      raise "poll failed"
    end
    if @disconnect_at_poll && @polls >= @disconnect_at_poll
      @lost = true
      return nil
    end
    if @notify_on && @completion && @last_job_write_ms && !@completion_sent &&
       @clock.now_ms - @last_job_write_ms >= @completion_after_ms
      @completion_sent = true
      push_all([@completion])
    end
    out = @queue
    @queue = []
    out
  end

  def disconnect
    @disconnects += 1
  end

  def job_writes
    return [] unless @job_start_index
    @writes[@job_start_index, @writes.size - @job_start_index]
  end

  def job_bytes
    out = ""
    list = job_writes
    i = 0
    while i < list.size
      out << list[i][1]
      i += 1
    end
    out
  end

  def query_writes
    return @writes unless @job_start_index
    @writes[0, @job_start_index]
  end

  private

  def push_all(list)
    i = 0
    while i < list.size
      @queue << list[i]
      i += 1
    end
  end
end
