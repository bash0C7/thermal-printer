require "json"
require "open3"
require "fileutils"

module DeviceGate
  class Failure < StandardError; end

  REPO = File.expand_path("..", __dir__)
  S1_DIR = File.join(REPO, "build", "device", "s1")
  SWIFT_SCRATCH = File.join(REPO, "build", "device", "swift")
  CORE_PACKAGE = File.join(REPO, "app", "Core")
  CLI = File.join(REPO, "bin", "phomemo-print")
  VM = File.join(REPO, "vendor", "R2P2-darwin", "build", "host", "bin", "picoruby")
  VM_SOURCE_GLOBS = %w[mrbgems/picoruby-phomemo-thermal-printer/**/* cli/**/*].freeze

  PBM_WIDTH = 384
  ROW_BYTES = 48
  MAX_ROWS = 400
  MAX_BLOCK_ROWS = 255
  INFO_OPS = [0x07, 0x08, 0x09, 0x0e, 0x11, 0x12, 0x13].freeze
  RASTER_FIXED = [0x76, 0x30, 0x00, 0x30, 0x00].freeze
  TABLE_HEADER = %w[# name ok error warnings acks chunks max_write state after_send_ms elapsed_ms].freeze

  def self.require_device_ok(env)
    raise Failure, "refusing to print: set DEVICE_OK=1 to allow printing on the real device" unless env["DEVICE_OK"] == "1"
  end

  def self.read_result(path)
    raise Failure, "result file not found: #{path}" unless File.exist?(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    raise Failure, "result file is not JSON: #{path}: #{e.message}"
  end

  def self.verify_print_result(path)
    data = read_result(path)
    raise Failure, "print did not succeed: ok=#{data['ok'].inspect} error=#{data['error'].inspect}" unless data["ok"] == true
    acks = data.dig("notify", "acks")
    chunks = data.dig("job", "chunks")
    unless acks.is_a?(Integer) && chunks.is_a?(Integer) && chunks > 0 && acks == chunks
      raise Failure, "notify acks do not match job chunks: acks=#{acks.inspect} chunks=#{chunks.inspect}"
    end
    data
  end

  def self.byte_at(bytes, index)
    raise Failure, "truncated command at offset #{index}" if index >= bytes.bytesize
    bytes.getbyte(index)
  end

  def self.audit_stream(bytes)
    bytes = bytes.b
    index = 0
    commands = 0
    blocks = 0
    rows = 0
    body = "".b
    while index < bytes.bytesize
      lead = bytes.getbyte(index)
      if lead == 0x1b
        op = byte_at(bytes, index + 1)
        if op == 0x40
          index += 2
        elsif op == 0x61
          align = byte_at(bytes, index + 2)
          raise Failure, "1b 61 #{'%02x' % align} at offset #{index}" unless align <= 2
          index += 3
        elsif op == 0x64
          byte_at(bytes, index + 2)
          index += 3
        else
          raise Failure, "disallowed command 1b #{'%02x' % op} at offset #{index}"
        end
      elsif lead == 0x1f
        raise Failure, "disallowed command 1f #{'%02x' % byte_at(bytes, index + 1)} at offset #{index}" unless byte_at(bytes, index + 1) == 0x11
        op = byte_at(bytes, index + 2)
        if op == 0x02
          density = byte_at(bytes, index + 3)
          raise Failure, "1f 11 02 #{'%02x' % density} at offset #{index}" unless density >= 1 && density <= 5
          index += 4
        elsif INFO_OPS.include?(op)
          index += 3
        else
          raise Failure, "disallowed command 1f 11 #{'%02x' % op} at offset #{index}"
        end
      elsif lead == 0x1d
        header = bytes.byteslice(index + 1, 5)
        unless header && header.bytes == RASTER_FIXED
          raise Failure, "disallowed command 1d #{'%02x' % byte_at(bytes, index + 1)} at offset #{index}"
        end
        y = byte_at(bytes, index + 6) + (byte_at(bytes, index + 7) << 8)
        raise Failure, "raster rows #{y} out of 1..#{MAX_BLOCK_ROWS} at offset #{index}" unless y >= 1 && y <= MAX_BLOCK_ROWS
        length = ROW_BYTES * y
        raise Failure, "raster at offset #{index} is truncated" if index + 8 + length > bytes.bytesize
        body << bytes.byteslice(index + 8, length)
        blocks += 1
        rows += y
        index += 8 + length
      else
        raise Failure, "disallowed byte #{'%02x' % lead} at offset #{index}"
      end
      commands += 1
    end
    { commands: commands, blocks: blocks, rows: rows, body: body }
  end

  def self.audit_dry_run(stdout, rows:, payload:)
    stream = "".b
    chunks = 0
    total = nil
    stdout.each_line do |line|
      line = line.chomp
      if (m = line.match(/\A(\d{4}) (\d+) ([0-9a-f]*)\z/))
        chunks += 1
        raise Failure, "chunk serial #{m[1]} out of order, expected #{chunks}" unless m[1].to_i == chunks
        raise Failure, "chunk #{m[1]} has an odd hex length" unless m[3].size.even?
        chunk = [m[3]].pack("H*")
        raise Failure, "chunk #{m[1]} length #{m[2]} does not match its #{chunk.bytesize} hex bytes" unless chunk.bytesize == m[2].to_i
        stream << chunk
      elsif (m = line.match(/\Atotal chunks=(\d+) bytes=(\d+) rows=(\d+)\z/))
        total = m.captures.map(&:to_i)
      elsif !line.empty?
        raise Failure, "unexpected dry-run line: #{line[0, 60]}"
      end
    end
    raise Failure, "dry-run printed no total line" unless total
    unless total == [chunks, stream.bytesize, rows]
      raise Failure, "dry-run total #{total.inspect} does not match chunks=#{chunks} bytes=#{stream.bytesize} rows=#{rows}"
    end
    audit = audit_stream(stream)
    raise Failure, "raster rows #{audit[:rows]} do not match the PBM rows #{rows}" unless audit[:rows] == rows
    raise Failure, "raster bytes differ from the PBM payload" unless audit[:body] == payload
    audit.merge(chunks: chunks, bytes: stream.bytesize)
  end

  def self.pbm_info(path)
    data = File.binread(path)
    head = data[/\AP4\n(\d+) (\d+)\n/n]
    raise Failure, "#{path}: not a P4 PBM" unless head
    width, rows = head.split("\n")[1].split(" ").map(&:to_i)
    raise Failure, "#{path}: width #{width} is not #{PBM_WIDTH}" unless width == PBM_WIDTH
    payload = data.byteslice(head.bytesize, data.bytesize)
    raise Failure, "#{path}: raster is #{payload.bytesize} bytes, expected #{rows * ROW_BYTES}" unless payload.bytesize == rows * ROW_BYTES
    { rows: rows, payload: payload }
  end

  def self.check_paper_budget(paths)
    total = paths.sum { |path| pbm_info(path)[:rows] }
    raise Failure, "#{total} rows in total exceeds the #{MAX_ROWS} row paper budget" if total > MAX_ROWS
    total
  end

  def self.vm_stale_reason(vm, sources)
    return "#{vm} not found - run `rake vm:build`" unless File.exist?(vm)
    newest = sources.select { |f| File.file?(f) }.max_by { |f| File.mtime(f) }
    return nil unless newest
    return nil if File.mtime(vm) > File.mtime(newest)
    "#{vm} is not newer than #{newest} - run `rake vm:build`"
  end

  def self.vm_sources
    VM_SOURCE_GLOBS.flat_map { |glob| Dir[File.join(REPO, glob)] }.select { |f| File.file?(f) }
  end

  def self.summary_row(number, name, path)
    data = read_result(path)
    [
      number.to_s, name, data["ok"].to_s, (data["error"] || "-").to_s,
      Array(data["warnings"]).join(",").then { |s| s.empty? ? "-" : s },
      data.dig("notify", "acks").to_s, data.dig("job", "chunks").to_s, data.dig("notify", "max_write").to_s,
      data.dig("completion", "state").to_s, data.dig("completion", "after_send_ms").to_s, data["elapsed_ms"].to_s
    ]
  rescue Failure
    [number.to_s, name, "missing"] + ["-"] * (TABLE_HEADER.size - 3)
  end

  def self.table(header, rows)
    all = [header] + rows
    widths = header.each_index.map { |i| all.map { |r| r[i].to_s.size }.max }
    all.map { |r| r.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join(" ").rstrip }.join("\n") + "\n"
  end

  def self.run_cli(*args)
    system(CLI, *args)
  end

  def self.dry_run(pbm, result_path)
    stdout, stderr, status = Open3.capture3(CLI, "--dry-run", "--result", result_path, pbm)
    raise Failure, "dry-run of #{pbm} exited #{status.exitstatus}: #{stderr}" unless status.success?
    stdout
  end
end

namespace :device do
  namespace :s1 do
    desc "Build the two S1 test PBMs under build/device/s1 and dry-run them through the allowlist audit (no device access)"
    task :prepare do
      require_relative "../tools/make_test_pbm"
      FileUtils.mkdir_p DeviceGate::S1_DIR
      FileUtils.mkdir_p DeviceGate::SWIFT_SCRATCH

      topline = File.join(DeviceGate::S1_DIR, "topline.pbm")
      photo = File.join(DeviceGate::S1_DIR, "photo.pbm")
      File.binwrite(topline, MakeTestPbm.render("topline"))
      sh "/usr/bin/swift", "run", "--package-path", DeviceGate::CORE_PACKAGE,
         "--scratch-path", DeviceGate::SWIFT_SCRATCH, "thermal-pbm", "--sample", photo

      begin
        total = DeviceGate.check_paper_budget([topline, photo])
        [["topline", topline], ["photo", photo]].each do |name, pbm|
          info = DeviceGate.pbm_info(pbm)
          result_path = File.join(DeviceGate::S1_DIR, "#{name}.dry.json")
          stdout = DeviceGate.dry_run(pbm, result_path)
          File.write(File.join(DeviceGate::S1_DIR, "#{name}.dry.txt"), stdout)
          audit = DeviceGate.audit_dry_run(stdout, rows: info[:rows], payload: info[:payload])
          puts "[device] #{name}: #{info[:rows]} rows, #{audit[:blocks]} blocks, #{audit[:chunks]} chunks, #{audit[:bytes]} bytes"
        end
        puts "[device] s1 prepared: 2 files, #{total} rows, allowlist ok"
      rescue DeviceGate::Failure => e
        abort "[device] s1 prepare failed: #{e.message}"
      end
    end

    desc "Run the S1 stage A on the real device (status, topline, photo, status). Requires DEVICE_OK=1"
    task :auto do
      begin
        DeviceGate.require_device_ok(ENV)
        reason = DeviceGate.vm_stale_reason(DeviceGate::VM, DeviceGate.vm_sources)
        raise DeviceGate::Failure, reason if reason
        topline = File.join(DeviceGate::S1_DIR, "topline.pbm")
        photo = File.join(DeviceGate::S1_DIR, "photo.pbm")
        [topline, photo].each do |pbm|
          raise DeviceGate::Failure, "#{pbm} not found - run `rake device:s1:prepare`" unless File.exist?(pbm)
        end
        DeviceGate.check_paper_budget([topline, photo])
      rescue DeviceGate::Failure => e
        abort "[device] s1 auto: #{e.message}"
      end

      steps = [
        ["status", %w[--status]],
        ["topline", [topline]],
        ["photo", [photo]],
        ["status-after", %w[--status]]
      ]
      ran = []
      print_table = lambda do
        rows = ran.map { |number, name, path| DeviceGate.summary_row(number, name, path) }
        puts DeviceGate.table(DeviceGate::TABLE_HEADER, rows)
      end
      stop = lambda do |path, message|
        print_table.call
        puts File.exist?(path) ? File.read(path) : "(no result file: #{path})"
        abort "[device] s1 auto stopped: #{message}"
      end

      steps.each_with_index do |(name, args), i|
        number = format("%02d", i + 1)
        path = File.join(DeviceGate::S1_DIR, "#{number}-#{name}.json")
        FileUtils.rm_f path
        ran << [number, name, path]
        puts "[device] #{number} #{name}"
        DeviceGate.run_cli(*args, "--result", path)
        begin
          if name == "status"
            data = DeviceGate.read_result(path)
            raise DeviceGate::Failure, "status failed: error=#{data['error'].inspect}" unless data["ok"] == true
          elsif name == "topline"
            DeviceGate.verify_print_result(path)
          end
        rescue DeviceGate::Failure => e
          stop.call(path, e.message)
        end
      end
      print_table.call
    end
  end
end
