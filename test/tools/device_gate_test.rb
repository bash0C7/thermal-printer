require "minitest/autorun"
require "rake"
require "json"
require "tmpdir"

load File.expand_path("../../rakelib/device.rake", __dir__)

class DeviceGateTest < Minitest::Test
  def write_result(dir, data)
    path = File.join(dir, "result.json")
    File.write(path, JSON.generate(data))
    path
  end

  def result(ok: true, acks: 10, chunks: 10)
    { "ok" => ok, "error" => ok ? nil : "disconnected", "notify" => { "acks" => acks }, "job" => { "chunks" => chunks } }
  end

  def raster(rows, fill = 0xaa)
    [0x1d, 0x76, 0x30, 0x00, 0x30, 0x00, rows & 0xff, rows >> 8].pack("C*") + [fill].pack("C") * (48 * rows)
  end

  def bin(*bytes)
    bytes.pack("C*")
  end

  def test_print_result_passes_when_acks_equal_chunks
    Dir.mktmpdir do |dir|
      DeviceGate.verify_print_result(write_result(dir, result))
    end
  end

  def test_print_result_fails_when_acks_differ_from_chunks
    Dir.mktmpdir do |dir|
      error = assert_raises(DeviceGate::Failure) { DeviceGate.verify_print_result(write_result(dir, result(acks: 9))) }
      assert_match(/acks=9.*chunks=10/, error.message)
    end
  end

  def test_print_result_fails_when_ok_is_false_even_if_acks_match
    Dir.mktmpdir do |dir|
      assert_raises(DeviceGate::Failure) { DeviceGate.verify_print_result(write_result(dir, result(ok: false))) }
    end
  end

  def test_print_result_fails_when_the_file_is_missing
    Dir.mktmpdir do |dir|
      assert_raises(DeviceGate::Failure) { DeviceGate.verify_print_result(File.join(dir, "nope.json")) }
    end
  end

  def test_print_result_fails_when_the_file_is_not_json
    Dir.mktmpdir do |dir|
      path = File.join(dir, "result.json")
      File.write(path, "{")
      assert_raises(DeviceGate::Failure) { DeviceGate.verify_print_result(path) }
    end
  end

  def test_print_result_fails_when_no_chunk_was_sent
    Dir.mktmpdir do |dir|
      assert_raises(DeviceGate::Failure) { DeviceGate.verify_print_result(write_result(dir, result(acks: 0, chunks: 0))) }
    end
  end

  def test_print_result_fails_when_the_counts_are_absent
    Dir.mktmpdir do |dir|
      assert_raises(DeviceGate::Failure) { DeviceGate.verify_print_result(write_result(dir, { "ok" => true })) }
    end
  end

  def test_device_ok_gate_requires_exactly_one
    DeviceGate.require_device_ok({ "DEVICE_OK" => "1" })
    assert_raises(DeviceGate::Failure) { DeviceGate.require_device_ok({}) }
    assert_raises(DeviceGate::Failure) { DeviceGate.require_device_ok({ "DEVICE_OK" => "0" }) }
    assert_raises(DeviceGate::Failure) { DeviceGate.require_device_ok({ "DEVICE_OK" => "" }) }
  end

  def test_stream_accepts_every_allowlisted_command
    stream = bin(0x1b, 0x40) + bin(0x1b, 0x61, 0x02) + bin(0x1f, 0x11, 0x02, 0x05) +
             bin(0x1f, 0x11, 0x07) + bin(0x1f, 0x11, 0x13) + raster(3) + raster(255) + bin(0x1b, 0x64, 0xff)
    audit = DeviceGate.audit_stream(stream)
    assert_equal 258, audit[:rows]
    assert_equal 2, audit[:blocks]
    assert_equal 8, audit[:commands]
  end

  def test_stream_rejects_info_ops_outside_the_allowlist
    [0x14, 0x15, 0x03, 0x0a, 0x10, 0xff].each do |op|
      assert_raises(DeviceGate::Failure, op.to_s) { DeviceGate.audit_stream(bin(0x1f, 0x11, op)) }
    end
  end

  def test_stream_rejects_density_outside_one_to_five
    [0x00, 0x06].each do |n|
      assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bin(0x1f, 0x11, 0x02, n)) }
    end
  end

  def test_stream_rejects_unknown_escape_and_group_separator_commands
    [bin(0x1b, 0x4e, 0x04, 0x01), bin(0x1b, 0x37, 0x01), bin(0x1d, 0x7c, 0x01), bin(0x1d, 0x67, 0x6e), bin(0x1f, 0x12, 0x02)].each do |bytes|
      assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bytes) }
    end
  end

  def test_stream_rejects_alignment_outside_zero_to_two
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bin(0x1b, 0x61, 0x03)) }
  end

  def test_stream_rejects_a_raster_with_zero_or_over_255_rows
    zero = bin(0x1d, 0x76, 0x30, 0x00, 0x30, 0x00, 0x00, 0x00)
    over = bin(0x1d, 0x76, 0x30, 0x00, 0x30, 0x00, 0x00, 0x01) + "\x00".b * (48 * 256)
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(zero) }
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(over) }
  end

  def test_stream_rejects_a_raster_header_with_other_parameters
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bin(0x1d, 0x76, 0x30, 0x01, 0x30, 0x00, 0x01, 0x00) + "\x00".b * 48) }
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bin(0x1d, 0x76, 0x30, 0x00, 0x20, 0x00, 0x01, 0x00) + "\x00".b * 48) }
  end

  def test_stream_rejects_a_truncated_raster_and_a_truncated_command
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(raster(2).byteslice(0, 8 + 48 * 2 - 1)) }
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bin(0x1f, 0x11)) }
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(bin(0x1b)) }
  end

  def test_stream_rejects_trailing_bytes_after_a_raster
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_stream(raster(1) + bin(0x00)) }
  end

  def hex_lines(stream, size)
    lines = []
    offset = 0
    while offset < stream.bytesize
      piece = stream.byteslice(offset, size)
      lines << format("%04d %d %s", lines.size + 1, piece.bytesize, piece.unpack1("H*"))
      offset += size
    end
    lines
  end

  def dry_run_output(stream, size: 128, rows: nil, total: nil)
    lines = hex_lines(stream, size)
    rows ||= stream.bytesize / 48
    total ||= "total chunks=#{lines.size} bytes=#{stream.bytesize} rows=#{rows}"
    (lines + [total]).join("\n") + "\n"
  end

  def sample_stream
    bin(0x1b, 0x40) + bin(0x1b, 0x61, 0x00) + bin(0x1f, 0x11, 0x02, 0x04) + raster(2, 0x55) + bin(0x1b, 0x64, 0x03)
  end

  def test_dry_run_audit_returns_the_chunk_count_and_checks_rows_and_payload
    stream = sample_stream
    audit = DeviceGate.audit_dry_run(dry_run_output(stream, rows: 2), rows: 2, payload: "\x55".b * 96)
    assert_equal 2, audit[:rows]
    assert_equal hex_lines(stream, 128).size, audit[:chunks]
  end

  def test_dry_run_audit_reassembles_a_stream_cut_at_odd_places
    audit = DeviceGate.audit_dry_run(dry_run_output(sample_stream, size: 7, rows: 2), rows: 2, payload: "\x55".b * 96)
    assert_equal 2, audit[:rows]
  end

  def test_dry_run_audit_fails_when_the_rows_do_not_match_the_pbm
    assert_raises(DeviceGate::Failure) do
      DeviceGate.audit_dry_run(dry_run_output(sample_stream, rows: 2), rows: 3, payload: "\x55".b * 144)
    end
  end

  def test_dry_run_audit_fails_when_the_payload_differs_from_the_pbm
    assert_raises(DeviceGate::Failure) do
      DeviceGate.audit_dry_run(dry_run_output(sample_stream, rows: 2), rows: 2, payload: "\x54".b * 96)
    end
  end

  def test_dry_run_audit_fails_when_the_total_line_disagrees
    output = dry_run_output(sample_stream, rows: 2, total: "total chunks=99 bytes=1 rows=2")
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_dry_run(output, rows: 2, payload: "\x55".b * 96) }
  end

  def test_dry_run_audit_fails_when_a_chunk_length_disagrees_with_its_hex
    output = dry_run_output(sample_stream, rows: 2).sub(/\A0001 (\d+)/) { "0001 #{$1.to_i + 1}" }
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_dry_run(output, rows: 2, payload: "\x55".b * 96) }
  end

  def test_dry_run_audit_fails_on_a_disallowed_command_in_the_hex
    stream = bin(0x1b, 0x40) + bin(0x1f, 0x11, 0x15)
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_dry_run(dry_run_output(stream, rows: 0), rows: 0, payload: "".b) }
  end

  def test_dry_run_audit_fails_when_there_is_no_total_line_or_a_stray_line
    lines = hex_lines(sample_stream, 128).join("\n")
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_dry_run(lines, rows: 2, payload: "\x55".b * 96) }
    assert_raises(DeviceGate::Failure) { DeviceGate.audit_dry_run("noise\n" + dry_run_output(sample_stream, rows: 2), rows: 2, payload: "\x55".b * 96) }
  end

  def write_pbm(dir, name, rows, width: 384)
    path = File.join(dir, name)
    File.binwrite(path, "P4\n#{width} #{rows}\n".b + "\x01".b * ((width / 8) * rows))
    path
  end

  def test_pbm_info_returns_rows_and_payload
    Dir.mktmpdir do |dir|
      info = DeviceGate.pbm_info(write_pbm(dir, "a.pbm", 5))
      assert_equal 5, info[:rows]
      assert_equal "\x01".b * (48 * 5), info[:payload]
    end
  end

  def test_pbm_info_rejects_a_wrong_width_and_a_short_raster
    Dir.mktmpdir do |dir|
      assert_raises(DeviceGate::Failure) { DeviceGate.pbm_info(write_pbm(dir, "w.pbm", 5, width: 256)) }
      short = File.join(dir, "s.pbm")
      File.binwrite(short, "P4\n384 5\n".b + "\x00".b * 100)
      assert_raises(DeviceGate::Failure) { DeviceGate.pbm_info(short) }
    end
  end

  def test_paper_budget_allows_up_to_400_rows_in_total
    Dir.mktmpdir do |dir|
      a = write_pbm(dir, "a.pbm", 96)
      b = write_pbm(dir, "b.pbm", 304)
      assert_equal 400, DeviceGate.check_paper_budget([a, b])
    end
  end

  def test_paper_budget_fails_over_400_rows_in_total
    Dir.mktmpdir do |dir|
      a = write_pbm(dir, "a.pbm", 96)
      b = write_pbm(dir, "b.pbm", 305)
      error = assert_raises(DeviceGate::Failure) { DeviceGate.check_paper_budget([a, b]) }
      assert_match(/401/, error.message)
    end
  end

  def test_vm_is_stale_when_a_source_is_newer_or_equal
    Dir.mktmpdir do |dir|
      vm = File.join(dir, "picoruby")
      src = File.join(dir, "session.rb")
      File.write(vm, "")
      File.write(src, "")
      File.utime(Time.at(1000), Time.at(1000), vm)
      File.utime(Time.at(2000), Time.at(2000), src)
      assert_match(/vm:build/, DeviceGate.vm_stale_reason(vm, [src]))
      File.utime(Time.at(1000), Time.at(1000), src)
      assert_match(/vm:build/, DeviceGate.vm_stale_reason(vm, [src]))
    end
  end

  def test_vm_is_fresh_when_newer_than_every_source
    Dir.mktmpdir do |dir|
      vm = File.join(dir, "picoruby")
      src = File.join(dir, "session.rb")
      File.write(vm, "")
      File.write(src, "")
      File.utime(Time.at(3000), Time.at(3000), vm)
      File.utime(Time.at(2000), Time.at(2000), src)
      assert_nil DeviceGate.vm_stale_reason(vm, [src])
    end
  end

  def test_vm_is_stale_when_it_does_not_exist
    Dir.mktmpdir do |dir|
      assert_match(/vm:build/, DeviceGate.vm_stale_reason(File.join(dir, "picoruby"), []))
    end
  end

  def test_summary_row_lists_the_fields_of_a_result
    Dir.mktmpdir do |dir|
      data = result.merge(
        "warnings" => ["battery_low"],
        "notify" => { "acks" => 10, "max_write" => 128 },
        "completion" => { "state" => "notified", "after_send_ms" => 2310 },
        "elapsed_ms" => 21034
      )
      row = DeviceGate.summary_row(2, "topline", write_result(dir, data))
      assert_equal ["2", "topline", "true", "-", "battery_low", "10", "10", "128", "notified", "2310", "21034"], row
    end
  end

  def test_summary_row_marks_a_missing_result_instead_of_raising
    Dir.mktmpdir do |dir|
      row = DeviceGate.summary_row(3, "photo", File.join(dir, "nope.json"))
      assert_equal "3", row[0]
      assert_equal "photo", row[1]
      assert_equal "missing", row[2]
    end
  end

  def test_table_aligns_columns
    text = DeviceGate.table(%w[a bb], [%w[1 2], %w[333 4]])
    assert_equal ["a   bb", "1   2", "333 4"], text.lines.map(&:rstrip)
  end
end
