module PhomemoThermalPrinter
  class SessionBase
    POLL_MS = 20
    QUERY_WAIT_MS = 1500
    PAIRING_WAIT_MS = 6000
    SUBSCRIBE_SETTLE_MS = 200
    CONNECT_TIMEOUT_MS = 10_000
    LOW_BATTERY_WARN = 10
    HEX_DIGITS = "0123456789abcdef"
    QUERY_KEYS = {
      0x08 => "battery", 0x11 => "paper", 0x12 => "cover", 0x13 => "temperature",
      0x07 => "firmware", 0x09 => "serial", 0x0e => "auto_off"
    }
    EVENT_KEYS = {
      battery: "battery", paper: "paper", cover: "cover", temperature: "temperature",
      firmware: "firmware", serial: "serial", auto_off: "auto_off"
    }

    def initialize(transport, clock:, sleeper:, device: "T02", connect_timeout_ms: CONNECT_TIMEOUT_MS)
      @transport = transport
      @clock = clock
      @sleeper = sleeper
      @device = device
      @connect_timeout_ms = connect_timeout_ms
      @decoder = StatusDecoder.new
      @status = {
        "battery" => nil, "paper" => nil, "cover" => nil, "temperature" => nil,
        "firmware" => nil, "serial" => nil, "auto_off" => nil
      }
      @status_seen = false
      @status_silent = false
      @events = []
      @acks_total = 0
      @acks_at_job_start = 0
      @max_write = nil
      @phase = :query
      @alert = nil
      @completed = false
      @connected = false
      @subscribed = false
      @job_started = false
      @last_write_ms = nil
      @error_hint = nil
      @result = nil
    end

    private

    def perform(mode, job)
      start = @clock.now_ms
      @result = Result.new(mode)
      error = nil
      begin
        error = execute(job)
      ensure
        @transport.disconnect if @connected
      end
      build_result(error, start)
    end

    def build_result(error, start)
      r = @result
      r.fail_with(error, @error_hint) if error
      r.status = @status if @status_seen
      battery = @status["battery"]
      r.add_warning("battery_low") if battery && battery <= LOW_BATTERY_WARN
      if @subscribed
        acks = @job_started ? @acks_total - @acks_at_job_start : 0
        r.notify = {"acks" => acks, "max_write" => @max_write, "events" => @events}
      end
      r.elapsed_ms = @clock.now_ms - start
      r
    end

    def open_link
      return "not_found" unless @transport.connect(@device, @connect_timeout_ms)
      @connected = true
      report = @transport.gatt_report
      return "wrong_device" unless report["service"] && report["write"] && report["notify"]
      @transport.subscribe(SUBSCRIBE_SETTLE_MS)
      @subscribed = true
      return "disconnected" unless drain
      nil
    end

    def check_status(ops)
      error = query_round(ops)
      return error if error
      unless @status_seen
        error = wait_for_any_reply(PAIRING_WAIT_MS)
        return error if error
        unless @status_seen
          @transport.subscribe(SUBSCRIBE_SETTLE_MS)
          return "disconnected" unless drain
        end
        error = query_round(ops)
        return error if error
      end
      @status_silent = !@status_seen
      nil
    end

    def query_round(ops)
      i = 0
      while i < ops.size
        @sleeper.sleep_ms(POLL_MS) if i > 0
        emit(Command.query(ops[i]))
        i += 1
      end
      deadline = @clock.now_ms + QUERY_WAIT_MS
      while true
        return "disconnected" unless drain
        return nil if all_seen?(ops)
        return nil if @clock.now_ms >= deadline
        @sleeper.sleep_ms(POLL_MS)
      end
    end

    def wait_for_any_reply(ms)
      deadline = @clock.now_ms + ms
      while true
        return "disconnected" unless drain
        return nil if @status_seen
        return nil if @clock.now_ms >= deadline
        @sleeper.sleep_ms(POLL_MS)
      end
    end

    def all_seen?(ops)
      i = 0
      while i < ops.size
        return false if @status[QUERY_KEYS[ops[i]]].nil?
        i += 1
      end
      true
    end

    def emit(bytes)
      @transport.write_chunk(bytes)
      @completed = false
      @last_write_ms = @clock.now_ms
    end

    def drain
      notes = @transport.poll_notifications
      return false if notes.nil?
      i = 0
      while i < notes.size
        events = @decoder.feed(notes[i])
        j = 0
        while j < events.size
          handle(events[j])
          j += 1
        end
        i += 1
      end
      true
    end

    def handle(event)
      type = event[0]
      if type == :ack
        @acks_total += 1
      elsif type == :max_write
        @max_write = event[1]
      elsif type == :print_complete
        @completed = true
        @events << "1a0f0c"
      elsif type == :print_failed
        @alert = "print_failed" if @phase == :job
        @events << "1a0f#{hex_byte(event[1])}"
      elsif type == :canceled
        @alert = "canceled" if @phase == :job
        @events << "1a0bb8"
      elsif type == :unknown
        @events << event[1]
      else
        store_status(event)
      end
    end

    def store_status(event)
      key = EVENT_KEYS[event[0]]
      return if key.nil?
      value = event[1]
      value = value.to_s if value.is_a?(Symbol)
      @status[key] = value
      @status_seen = true
      note_hazard(event) if @phase == :job
    end

    def note_hazard(event)
      if event[0] == :cover && event[1] == :open
        raise_alert("cover_open", "1a0599")
      elsif event[0] == :paper && event[1] == :out
        raise_alert("paper_out", "1a0688")
      elsif event[0] == :temperature && event[1] == :overheat
        raise_alert("overheat", "1a03a9")
      end
    end

    def raise_alert(error, hex)
      @alert = error unless @alert
      @events << hex
    end

    def hex_byte(n)
      HEX_DIGITS[n >> 4] + HEX_DIGITS[n & 0x0f]
    end
  end

  class PrintSession < SessionBase
    PRECHECK_OPS = [0x11, 0x12, 0x08, 0x13]
    MIN_AFTER_SEND_MS = 2000
    ROWS_PER_SECOND = 48
    EMPTY_BATTERY = 5
    PRECHECK_MISSING_HINT = "The paper or cover status did not arrive, so nothing was printed. On the first run, accept the macOS pairing prompt, then run again."
    DISCONNECTED_IN_JOB_HINT = "The printer disconnected during the job and may hold an unfinished raster block. Turn the printer off and on before the next print."

    def initialize(transport, clock:, sleeper:, device: "T02", chunk: 128, interval: 20, density: 4,
                   connect_timeout_ms: CONNECT_TIMEOUT_MS)
      super(transport, clock: clock, sleeper: sleeper, device: device, connect_timeout_ms: connect_timeout_ms)
      @chunk = chunk
      @interval = interval
      @density = density
      @chunks = 0
      @effective_chunk = chunk
      @applied_max = nil
      @sent = 0
      @pushed = 0
      @tracked = []
    end

    def run(job)
      perform("print", job)
    end

    private

    def execute(job)
      error = open_link
      return error if error
      error = check_status(PRECHECK_OPS)
      return error if error
      if @status["paper"].nil? || @status["cover"].nil?
        @error_hint = PRECHECK_MISSING_HINT
        return "status_unavailable"
      end
      @result.add_warning("status_partial") unless all_seen?(PRECHECK_OPS)
      error = precheck_verdict
      return error if error
      error = send_job(job)
      @error_hint = DISCONNECTED_IN_JOB_HINT if error == "disconnected"
      @result.add_warning("ack_mismatch") if error.nil? && @acks_total - @acks_at_job_start < @chunks
      @result.job = job_report(job) if @job_started
      error
    end

    def precheck_verdict
      return "paper_out" if @status["paper"] == "out"
      return "cover_open" if @status["cover"] == "open"
      return "overheat" if @status["temperature"] == "overheat"
      battery = @status["battery"]
      return "low_battery" if battery && battery <= EMPTY_BATTERY
      nil
    end

    def send_job(job)
      chunker = Chunker.new(@chunk)
      @phase = :job
      @acks_at_job_start = @acks_total
      @job_started = true
      begin
        stream_job(job, chunker)
      rescue FormatError => e
        @error_hint = e.message
        stop_job("invalid_input")
      rescue StandardError => e
        @error_hint = "The job stopped on an unexpected error (#{e.message}) and the printer may hold an unfinished raster block. Turn the printer off and on before the next print."
        stop_job("unknown")
      end
    end

    def stream_job(job, chunker)
      while (segment = job.next_segment)
        unless Command.allowed?(segment)
          @error_hint = "a job segment is not an allowed printer command; the job was stopped"
          return stop_job("print_failed")
        end
        apply_limit(chunker)
        track_segment(segment)
        error = send_chunks(chunker.push(segment))
        return stop_job(error) if error
      end
      rest = chunker.flush
      if rest
        error = send_chunks([rest])
        return stop_job(error) if error
      end
      await_completion(job)
    end

    def track_segment(segment)
      keep = []
      tracked = @tracked
      sent = @sent
      i = 0
      while i < tracked.size
        entry = tracked[i]
        keep << entry if entry[0] + entry[1].bytesize > sent
        i += 1
      end
      keep << [@pushed, segment]
      @pushed += segment.bytesize
      @tracked = keep
    end

    def stop_job(error)
      return error if error == "disconnected"
      fill = unfinished_command_fill
      return error if fill.nil?
      begin
        return "disconnected" if write_fill(fill)
      rescue StandardError
        return "disconnected"
      end
      error
    end

    def unfinished_command_fill
      tracked = @tracked
      sent = @sent
      i = 0
      while i < tracked.size
        start = tracked[i][0]
        segment = tracked[i][1]
        size = segment.bytesize
        offset = sent - start
        if offset > 0 && offset < size
          return "\x00" * (size - offset) if segment.getbyte(0) == 0x1d
          return segment.byteslice(offset, size - offset - 1) + "\x00" if segment.getbyte(1) == 0x64
          return nil
        end
        i += 1
      end
      nil
    end

    def write_fill(fill)
      chunker = Chunker.new(@effective_chunk)
      list = chunker.push(fill)
      rest = chunker.flush
      list << rest if rest
      i = 0
      while i < list.size
        return true if send_chunk(list[i], true)
        i += 1
      end
      false
    end

    def apply_limit(chunker)
      max_write = @max_write
      return if max_write.nil? || max_write == @applied_max
      cap = max_write < Chunker::MIN_SIZE ? Chunker::MIN_SIZE : max_write
      chunker.limit(cap)
      @effective_chunk = cap if cap < @effective_chunk
      @applied_max = max_write
    end

    def send_chunks(list)
      i = 0
      while i < list.size
        error = send_chunk(list[i])
        return error if error
        i += 1
      end
      nil
    end

    def send_chunk(chunk, ignore_alert = false)
      last = @last_write_ms
      if last
        wait = @interval - (@clock.now_ms - last)
        @sleeper.sleep_ms(wait) if wait > 0
      end
      emit(chunk)
      @chunks += 1
      @sent += chunk.bytesize
      return "disconnected" unless drain
      return nil if ignore_alert
      @alert
    end

    def await_completion(job)
      cap = job.rows * 1000 / ROWS_PER_SECOND + 2000
      last_block_rows = job.rows > 255 ? 255 : job.rows
      minimum = last_block_rows * 1000 / ROWS_PER_SECOND
      minimum = MIN_AFTER_SEND_MS if minimum < MIN_AFTER_SEND_MS
      last = @last_write_ms
      while true
        elapsed = @clock.now_ms - last
        if @completed && elapsed >= minimum
          @result.complete("notified", elapsed)
          return nil
        end
        if elapsed >= cap
          @result.complete("unconfirmed", elapsed)
          @result.add_warning("completion_unconfirmed")
          return nil
        end
        @sleeper.sleep_ms(POLL_MS)
        return "disconnected" unless drain
        return @alert if @alert
      end
    end

    def job_report(job)
      {
        "rows" => job.rows, "blocks" => job.blocks, "bytes" => job.bytes, "chunks" => @chunks,
        "chunk_size" => @effective_chunk, "interval_ms" => @interval, "density" => @density
      }
    end
  end

  class StatusSession < SessionBase
    ALL_OPS = [0x08, 0x11, 0x12, 0x13, 0x07, 0x09, 0x0e]

    def query
      perform("status", nil)
    end

    private

    def execute(_job)
      error = open_link
      return error if error
      error = check_status(ALL_OPS)
      return error if error
      return "status_unavailable" if @status_silent
      nil
    end
  end
end
