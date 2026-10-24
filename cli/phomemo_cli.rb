require 'json'

module PhomemoCLI
  EXIT_CODES = {
    "unknown" => 1,
    "usage" => 2,
    "not_found" => 10,
    "wrong_device" => 11,
    "busy" => 12,
    "timeout" => 13,
    "disconnected" => 14,
    "status_unavailable" => 15,
    "paper_out" => 20,
    "cover_open" => 21,
    "overheat" => 22,
    "low_battery" => 23,
    "print_failed" => 30,
    "canceled" => 31,
  }

  EXIT_ALIASES = {"invalid_input" => "usage"}

  def self.exit_code_for(error)
    return 0 if error.nil?
    name = EXIT_ALIASES[error] || error
    EXIT_CODES[name] || EXIT_CODES["unknown"]
  end

  class Options
    DEFAULT_FEED = 1

    attr_reader :device, :density, :chunk, :interval, :result, :pbm, :feed, :error, :message
    attr_reader :dry_run, :status, :png

    def self.parse(argv, env: ENV)
      new.parse(argv, env)
    end

    def initialize
      @device = "T02"
      @density = 4
      @chunk = 128
      @interval = 20
      @result = nil
      @pbm = nil
      @png = nil
      @feed = DEFAULT_FEED
      @dry_run = false
      @status = false
      @error = nil
      @message = nil
    end

    def parse(argv, env)
      i = 0
      while i < argv.size
        arg = argv[i]
        case arg
        when "--dry-run"
          @dry_run = true
        when "--status"
          @status = true
        when "--device", "--result", "--png"
          i += 1
          return fail_usage("#{arg} needs a value") if i >= argv.size
          return fail_usage("#{arg} must not be empty") if argv[i].empty?
          case arg
          when "--device" then @device = argv[i]
          when "--result" then @result = argv[i]
          else @png = argv[i]
          end
        when "--density", "--chunk", "--interval"
          i += 1
          return fail_usage("#{arg} needs a value") if i >= argv.size
          return self unless read_integer(arg, argv[i])
        else
          return fail_usage("unknown option #{arg}") if arg.start_with?("--")
          return fail_usage("only one PBM file can be given") if @pbm
          @pbm = arg
        end
        i += 1
      end
      return self unless read_feed(env)
      check_target
      self
    end

    private

    def fail_usage(message)
      @error = :usage
      @message = message
      self
    end

    def read_integer(name, text)
      value = to_integer(text)
      range = RANGES[name]
      if value.nil? || value < range[0] || value > range[1]
        fail_usage("#{name} must be an integer from #{range[0]} to #{range[1]}")
        return false
      end
      case name
      when "--density" then @density = value
      when "--chunk" then @chunk = value
      else @interval = value
      end
      true
    end

    def read_feed(env)
      text = env["PHOMEMO_FEED"]
      return true if text.nil?
      value = to_integer(text)
      if value.nil? || value > 255
        fail_usage("PHOMEMO_FEED must be an integer from 0 to 255")
        return false
      end
      @feed = value
      true
    end

    def check_target
      return fail_usage("--png needs --dry-run") if @png && !@dry_run
      if @status
        fail_usage("--status takes no PBM file") if @pbm
      elsif @pbm.nil?
        fail_usage("a PBM file is required")
      end
    end

    def to_integer(text)
      return nil if text.empty? || text.bytesize > 9
      i = 0
      while i < text.bytesize
        b = text.getbyte(i)
        return nil if b < 48 || b > 57
        i += 1
      end
      text.to_i
    end

    RANGES = {"--density" => [1, 5], "--chunk" => [20, 182], "--interval" => [10, 1000]}
  end

  class Lock
    DEFAULT_PATH = "/tmp/phomemo-print.lock"
    GAP_MS = 1500

    attr_reader :last_finished_ms

    def self.acquire(path = DEFAULT_PATH, last_finished_ms: nil)
      File.open(path, "w") { |f| f.write("") } unless File.exist?(path)
      file = File.open(path, "r+")
      if file.flock(File::LOCK_EX | File::LOCK_NB) == false
        file.close
        return nil
      end
      stored = file.read
      last = last_finished_ms
      last = stored.to_i if last.nil? && stored && !stored.empty?
      new(path, file, last)
    end

    def initialize(path, file, last_finished_ms)
      @path = path
      @file = file
      @last_finished_ms = last_finished_ms
    end

    def wait_for_gap(clock, sleeper)
      return if @last_finished_ms.nil?
      elapsed = clock.now_ms - @last_finished_ms
      return if elapsed < 0
      remaining = GAP_MS - elapsed
      sleeper.sleep_ms(remaining) if remaining > 0
    end

    def release(now_ms:)
      File.open(@path, "w") { |f| f.write(now_ms.to_s) }
      @file.flock(File::LOCK_UN)
      @file.close
    end
  end

  class ResultFile
    def self.write(path, result)
      tmp = "#{path}.tmp"
      File.open(tmp, "w") { |f| f.write(JSON.generate(result)) }
      File.rename(tmp, path)
    end
  end

  class PngFile
    def self.write(path, bytes)
      tmp = "#{path}.tmp"
      File.open(tmp, "w") { |f| f.write(bytes) }
      File.rename(tmp, path)
    end
  end

  class SystemClock
    def now_ms
      Machine.board_millis
    end
  end

  class SystemSleeper
    def sleep_ms(ms)
      Kernel.sleep_ms(ms)
    end
  end

  class StdoutLines
    def <<(line)
      puts line
      self
    end
  end

  class StderrLines
    def <<(line)
      $stderr.puts line
      self
    end
  end

  class Runner
    HEX_DIGITS = "0123456789abcdef"
    RASTER_COMMAND = 0x1d
    RASTER_HEADER_BYTES = 8
    NO_TRANSPORT_HINT = "this build has no BLE transport. Use --dry-run to list the bytes that would be sent."

    def initialize(argv, transport_factory:, stdout: nil, stderr: nil, lock_path: Lock::DEFAULT_PATH,
                   clock: nil, sleeper: nil, env: ENV)
      @argv = argv
      @transport_factory = transport_factory
      @stdout = stdout || StdoutLines.new
      @stderr = stderr || StderrLines.new
      @lock_path = lock_path
      @clock = clock || SystemClock.new
      @sleeper = sleeper || SystemSleeper.new
      @env = env
      @options = nil
      @chunk_count = 0
      @raster = nil
    end

    def run
      @options = Options.parse(@argv, env: @env)
      return fail_run("usage", @options.message) if @options.error
      return run_dry_run if @options.dry_run
      return run_status if @options.status
      run_print
    rescue StandardError => e
      fail_run("unknown", e.message)
    end

    private

    def mode_name
      return "dry_run" if @options.dry_run
      return "status" if @options.status
      "print"
    end

    def fail_run(error, hint)
      finish(PhomemoThermalPrinter::Result.failure(mode_name, error, hint: hint))
    end

    def finish(result)
      code = PhomemoCLI.exit_code_for(result.error)
      report = result.to_h(exit_code: code)
      if @options.result
        write_result_file(report)
      elsif result.mode != "dry_run"
        @stdout << JSON.generate(report)
      end
      if result.error
        line = "phomemo-print: #{result.error}"
        line = "#{line}: #{result.hint}" if result.hint
        @stderr << line
      end
      code
    end

    def write_result_file(report)
      ResultFile.write(@options.result, report)
    rescue StandardError => e
      @stdout << JSON.generate(report)
      @stderr << "phomemo-print: could not write the result file #{@options.result}: #{e.message}"
    end

    def with_pbm
      path = @options.pbm
      return fail_run("invalid_input", "PBM file not found: #{path}") unless File.exist?(path)
      io = File.open(path, "r")
      begin
        reader = PhomemoThermalPrinter::PbmReader.new(io)
        unless reader.complete_in?(File.size(path))
          raise PhomemoThermalPrinter::FormatError, "truncated raster"
        end
        yield reader
      rescue PhomemoThermalPrinter::FormatError => e
        fail_run("invalid_input", "#{path}: #{e.message}")
      ensure
        io.close
      end
    end

    def locked_run(mode)
      lock = Lock.acquire(@lock_path)
      return finish(PhomemoThermalPrinter::Result.failure(mode, "busy")) unless lock
      begin
        lock.wait_for_gap(@clock, @sleeper)
        result = yield
      ensure
        lock.release(now_ms: @clock.now_ms)
      end
      finish(result)
    end

    def new_job(reader)
      PhomemoThermalPrinter::Job.new(reader, density: @options.density, feed: @options.feed)
    end

    def run_status
      return fail_run("unknown", NO_TRANSPORT_HINT) if @transport_factory.nil?
      locked_run("status") do
        PhomemoThermalPrinter::StatusSession.new(
          @transport_factory.call, clock: @clock, sleeper: @sleeper, device: @options.device
        ).query
      end
    end

    def run_print
      with_pbm do |reader|
        next fail_run("unknown", NO_TRANSPORT_HINT) if @transport_factory.nil?
        locked_run("print") do
          PhomemoThermalPrinter::PrintSession.new(
            @transport_factory.call, clock: @clock, sleeper: @sleeper, device: @options.device,
            chunk: @options.chunk, interval: @options.interval, density: @options.density
          ).run(new_job(reader))
        end
      end
    end

    def run_dry_run
      with_pbm do |reader|
        job = new_job(reader)
        error = list_chunks(job)
        result = PhomemoThermalPrinter::Result.new("dry_run")
        if error
          result.fail_with(error, "a job segment is not an allowed printer command")
        else
          result.job = {
            "rows" => job.rows, "blocks" => job.blocks, "bytes" => job.bytes, "chunks" => @chunk_count,
            "chunk_size" => @options.chunk, "interval_ms" => @options.interval, "density" => @options.density
          }
          @stdout << "total chunks=#{@chunk_count} bytes=#{job.bytes} rows=#{job.rows}"
          write_png(job.rows)
        end
        finish(result)
      end
    end

    def list_chunks(job)
      chunker = PhomemoThermalPrinter::Chunker.new(@options.chunk)
      @chunk_count = 0
      @raster = @options.png ? "" : nil
      while (segment = job.next_segment)
        return "print_failed" unless PhomemoThermalPrinter::Command.allowed?(segment)
        collect_raster(segment)
        print_chunks(chunker.push(segment))
      end
      rest = chunker.flush
      print_chunks([rest]) if rest
      nil
    end

    def collect_raster(segment)
      return unless @raster
      return unless segment.getbyte(0) == RASTER_COMMAND
      @raster << segment.byteslice(RASTER_HEADER_BYTES, segment.bytesize - RASTER_HEADER_BYTES)
    end

    def write_png(rows)
      path = @options.png
      return unless path
      png = PhomemoThermalPrinter::PngWriter.encode(@raster, PhomemoThermalPrinter::PbmReader::WIDTH, rows)
      PngFile.write(path, png)
    rescue StandardError => e
      @stderr << "phomemo-print: could not write the PNG file #{path}: #{e.message}"
    end

    def print_chunks(list)
      i = 0
      while i < list.size
        @chunk_count += 1
        @stdout << "#{serial(@chunk_count)} #{list[i].bytesize} #{hex(list[i])}"
        i += 1
      end
    end

    def serial(n)
      s = n.to_s
      while s.size < 4
        s = "0#{s}"
      end
      s
    end

    def hex(bytes)
      out = ""
      i = 0
      while i < bytes.bytesize
        b = bytes.getbyte(i)
        out << HEX_DIGITS[b >> 4] << HEX_DIGITS[b & 0x0f]
        i += 1
      end
      out
    end
  end
end
