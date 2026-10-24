require 'json'

class RunnerTest < Picotest::Test
  HEX = "0123456789abcdef"

  def fixture_path(name)
    File.join(ENV["THERMAL_PRINTER_REPO_ROOT"], "mrbgems", "picoruby-phomemo-thermal-printer", "test", "fixtures", name)
  end

  def tmp_path(name, ext)
    @paths = [] unless @paths
    path = "/tmp/phomemo-cli-runnertest-#{name}-#{Machine.board_millis}.#{ext}"
    @paths << path
    @paths << path + ".tmp"
    path
  end

  def teardown
    return unless @paths
    i = 0
    while i < @paths.size
      File.delete(@paths[i]) if File.exist?(@paths[i])
      i += 1
    end
    @paths = []
  end

  def read_json(path)
    JSON.parse(File.open(path, "r") { |f| f.read })
  end

  def hex_of(bytes)
    out = ""
    i = 0
    while i < bytes.bytesize
      b = bytes.getbyte(i)
      out << HEX[b >> 4] << HEX[b & 15]
      i += 1
    end
    out
  end

  def ok_replies
    {
      "\x1f\x11\x11" => "\x1a\x06\x89",
      "\x1f\x11\x12" => "\x1a\x05\x98",
      "\x1f\x11\x08" => "\x1a\x04\x53",
      "\x1f\x11\x13" => "\x1a\x03\xa8",
    }
  end

  def all_replies
    ok_replies.merge(
      "\x1f\x11\x07" => "\x1a\x07\x03\x00\x07",
      "\x1f\x11\x09" => "\x1a\x08Q114E48T2580915",
      "\x1f\x11\x0e" => "\x1a\x09\x0c"
    )
  end

  def fake(**opts)
    FakeTransport.new(FakeClock.new, **opts)
  end

  def runner(argv, t = nil, lock: nil, out: [], err: [], env: {})
    factory = t ? lambda { t } : lambda { raise "must not connect" }
    PhomemoCLI::Runner.new(argv, transport_factory: factory, stdout: out, stderr: err,
                           lock_path: lock || tmp_path("lock", "lock"), env: env,
                           clock: t ? t.clock : nil, sleeper: t ? t.sleeper : nil)
  end

  def pbm_file(name, header, body_bytes)
    path = tmp_path(name, "pbm")
    File.open(path, "w") { |f| f.write(header + ("\x00" * body_bytes)) }
    path
  end

  def test_dry_run_never_builds_a_transport
    out = []
    code = runner(["--dry-run", fixture_path("stripes-600.pbm")], out: out).run
    assert_equal 0, code
    assert out.last.start_with?("total chunks=")
  end

  def test_dry_run_hex_concatenates_to_the_job_bytes
    out = []
    runner(["--dry-run", "--chunk", "182", fixture_path("stripes-600.pbm")], out: out).run
    hex = out[0..-2].map { |l| l.split(" ")[2] }.join
    assert hex.start_with?("1b401b61001f1102041d7630003000ff00")
    assert hex.end_with?("1b6401")
  end

  def test_dry_run_lines_carry_serial_length_and_hex
    out = []
    runner(["--dry-run", fixture_path("stripes-600.pbm")], out: out).run
    first = out[0].split(" ")
    assert_equal "0001", first[0]
    assert_equal "128", first[1]
    assert_equal 256, first[2].size
    assert first[2].start_with?("1b401b6100")
    assert out[1].start_with?("0002 128 ")
    assert_equal "total chunks=#{out.size - 1} bytes=28836 rows=600", out.last
  end

  def test_dry_run_summary_bytes_match_the_hex
    out = []
    runner(["--dry-run", "--chunk", "100", fixture_path("stripes-600.pbm")], out: out).run
    hex_chars = 0
    i = 0
    while i < out.size - 1
      hex_chars += out[i].split(" ")[2].size
      i += 1
    end
    assert_equal "bytes=#{hex_chars / 2}", out.last.split(" ")[2]
  end

  def test_dry_run_hex_equals_what_the_session_writes
    out = []
    runner(["--dry-run", fixture_path("stripes-600.pbm")], out: out).run
    dry = out[0..-2].map { |l| l.split(" ")[2] }.join
    t = fake(replies: ok_replies)
    code = runner([fixture_path("stripes-600.pbm")], t).run
    assert_equal 0, code
    sent = ""
    writes = t.job_writes
    j = 0
    while j < writes.size
      sent << writes[j][1]
      j += 1
    end
    assert_equal dry, hex_of(sent)
  end

  def test_the_feed_comes_from_the_environment
    out = []
    runner(["--dry-run", fixture_path("stripes-600.pbm")], out: out, env: {"PHOMEMO_FEED" => "7"}).run
    hex = out[0..-2].map { |l| l.split(" ")[2] }.join
    assert hex.end_with?("1b6407")
  end

  def test_dry_run_result_has_mode_dry_run_and_no_notify
    path = tmp_path("dry", "json")
    code = runner(["--dry-run", "--result", path, fixture_path("stripes-600.pbm")]).run
    assert_equal 0, code
    r = read_json(path)
    assert_equal "dry_run", r["mode"]
    assert_equal true, r["ok"]
    assert_equal 0, r["exit_code"]
    assert_equal 600, r["job"]["rows"]
    assert_equal 3, r["job"]["blocks"]
    assert_equal 128, r["job"]["chunk_size"]
    assert_nil r["notify"]
    assert_nil r["status"]
    assert_nil r["completion"]
  end

  def pbm_body(path)
    data = File.open(path, "r") { |f| f.read }
    data.byteslice(data.bytesize - 48 * 600, 48 * 600)
  end

  def test_png_writes_the_printed_bitmap_as_a_png
    png = tmp_path("preview", "png")
    out = []
    code = runner(["--dry-run", "--png", png, fixture_path("stripes-600.pbm")], out: out).run
    assert_equal 0, code
    expected = PhomemoThermalPrinter::PngWriter.encode(pbm_body(fixture_path("stripes-600.pbm")), 384, 600)
    assert_equal expected, File.open(png, "r") { |f| f.read }
    assert_false File.exist?(png + ".tmp")
  end

  def test_png_leaves_the_chunk_listing_unchanged
    plain = []
    runner(["--dry-run", fixture_path("stripes-600.pbm")], out: plain).run
    with_png = []
    runner(["--dry-run", "--png", tmp_path("same", "png"), fixture_path("stripes-600.pbm")], out: with_png).run
    assert_equal plain, with_png
  end

  def test_png_without_dry_run_is_a_usage_error
    png = tmp_path("nodry", "png")
    err = []
    code = runner(["--png", png, fixture_path("stripes-600.pbm")], err: err).run
    assert_equal 2, code
    assert err[0].include?("--png")
    assert_false File.exist?(png)
  end

  def test_png_with_status_is_a_usage_error
    code = runner(["--status", "--png", tmp_path("status", "png")]).run
    assert_equal 2, code
  end

  def test_png_needs_a_path
    code = runner(["--dry-run", fixture_path("stripes-600.pbm"), "--png"]).run
    assert_equal 2, code
  end

  def test_png_covers_every_block_of_the_job
    png = tmp_path("blocks", "png")
    runner(["--dry-run", "--png", png, fixture_path("stripes-600.pbm")]).run
    data = File.open(png, "r") { |f| f.read }
    assert_equal 600, (data.getbyte(20) << 24) | (data.getbyte(21) << 16) | (data.getbyte(22) << 8) | data.getbyte(23)
  end

  def test_a_png_that_cannot_be_written_keeps_the_exit_code_and_the_chunk_listing
    out = []
    err = []
    code = runner(["--dry-run", "--png", "/nonexistent-dir/preview.png", fixture_path("stripes-600.pbm")],
                  out: out, err: err).run
    assert_equal 0, code
    assert out.last.start_with?("total chunks=")
    assert_equal 1, err.size
    assert err[0].include?("PNG")
    assert err[0].include?("/nonexistent-dir/preview.png")
  end

  def test_a_print_with_the_fake_writes_an_ok_result
    path = tmp_path("print", "json")
    t = fake(replies: ok_replies)
    code = runner(["--result", path, fixture_path("stripes-600.pbm")], t).run
    assert_equal 0, code
    r = read_json(path)
    assert_equal true, r["ok"]
    assert_equal "print", r["mode"]
    assert_equal 0, r["exit_code"]
    assert_equal 600, r["job"]["rows"]
    assert_equal 3, r["job"]["blocks"]
    assert_equal "notified", r["completion"]["state"]
    assert_equal 83, r["status"]["battery"]
    assert_false File.exist?(path + ".tmp")
  end

  def test_chunk_interval_and_density_reach_the_session
    path = tmp_path("opts", "json")
    t = fake(replies: ok_replies)
    code = runner(["--chunk", "64", "--interval", "50", "--density", "2", "--result", path,
                   fixture_path("stripes-600.pbm")], t).run
    assert_equal 0, code
    r = read_json(path)
    assert_equal 64, r["job"]["chunk_size"]
    assert_equal 50, r["job"]["interval_ms"]
    assert_equal 2, r["job"]["density"]
    assert hex_of(t.job_writes[0][1]).start_with?("1b401b6100" + "1f110202")
  end

  def test_without_result_the_json_goes_to_stdout
    out = []
    t = fake(replies: ok_replies)
    code = runner([fixture_path("stripes-600.pbm")], t, out: out).run
    assert_equal 0, code
    assert_equal 1, out.size
    assert_equal "print", JSON.parse(out[0])["mode"]
  end

  def test_status_mode_reports_every_field
    path = tmp_path("status", "json")
    t = fake(replies: all_replies)
    code = runner(["--status", "--result", path], t).run
    assert_equal 0, code
    r = read_json(path)
    assert_equal "status", r["mode"]
    assert_equal true, r["ok"]
    assert_equal "3.0.7", r["status"]["firmware"]
    assert_equal "Q114E48T2580915", r["status"]["serial"]
    assert_nil r["job"]
    assert_equal 7, t.writes.size
  end

  def test_a_silent_printer_is_status_unavailable_with_exit_15
    path = tmp_path("silent", "json")
    t = fake(replies: {})
    code = runner(["--status", "--result", path], t).run
    assert_equal 15, code
    r = read_json(path)
    assert_equal "status_unavailable", r["error"]
    assert_equal 15, r["exit_code"]
    assert_equal false, r["ok"]
  end

  def test_not_found_is_exit_10_with_the_hint
    path = tmp_path("nf", "json")
    t = fake(found: false)
    code = runner(["--result", path, fixture_path("stripes-600.pbm")], t).run
    assert_equal 10, code
    r = read_json(path)
    assert_equal "not_found", r["error"]
    assert_equal 10, r["exit_code"]
    assert r["hint"].include?("power button")
    assert_equal 0, t.writes.size
  end

  def test_paper_out_is_exit_20_and_nothing_is_printed
    path = tmp_path("paper", "json")
    t = fake(replies: ok_replies.merge("\x1f\x11\x11" => "\x1a\x06\x88"))
    code = runner(["--result", path, fixture_path("stripes-600.pbm")], t).run
    assert_equal 20, code
    r = read_json(path)
    assert_equal "paper_out", r["error"]
    assert_nil r["job"]
    assert_equal 0, t.job_writes.size
  end

  def test_busy_is_returned_while_another_holds_the_lock
    lock = tmp_path("busy", "lock")
    path = tmp_path("busy", "json")
    other = PhomemoCLI::Lock.acquire(lock)
    code = runner(["--status", "--result", path], fake(replies: all_replies), lock: lock).run
    assert_equal 12, code
    r = read_json(path)
    assert_equal "busy", r["error"]
    assert_equal 12, r["exit_code"]
    assert_equal "status", r["mode"]
    other.release(now_ms: 0)
  end

  def test_the_busy_result_is_the_contract_fixture
    lock = tmp_path("busy3", "lock")
    path = tmp_path("busy3", "json")
    other = PhomemoCLI::Lock.acquire(lock)
    runner(["--status", "--result", path], lock: lock).run
    fixture = File.join(ENV["THERMAL_PRINTER_REPO_ROOT"], "test", "fixtures", "result_busy.json")
    assert_equal JSON.parse(File.open(fixture, "r") { |f| f.read }), read_json(path)
    other.release(now_ms: 0)
  end

  def test_busy_never_builds_a_transport
    lock = tmp_path("busy2", "lock")
    other = PhomemoCLI::Lock.acquire(lock)
    code = runner(["--status", "--result", tmp_path("busy2", "json")], lock: lock).run
    assert_equal 12, code
    other.release(now_ms: 0)
  end

  def test_the_lock_is_released_with_the_finish_time
    lock = tmp_path("rel", "lock")
    t = fake(replies: all_replies)
    runner(["--status", "--result", tmp_path("rel", "json")], t, lock: lock).run
    again = PhomemoCLI::Lock.acquire(lock)
    assert_not_nil again
    assert_equal t.clock.now_ms, again.last_finished_ms
    again.release(now_ms: 0)
  end

  def test_a_job_right_after_the_last_one_waits_out_the_1500ms_gap
    lock = tmp_path("gap", "lock")
    t = fake(replies: all_replies)
    PhomemoCLI::Lock.acquire(lock).release(now_ms: t.clock.now_ms)
    runner(["--status", "--result", tmp_path("gap", "json")], t, lock: lock).run
    assert_equal 1500, t.sleeper.slept[0]
  end

  def test_an_exception_in_the_session_is_an_unknown_result_with_exit_1_and_the_lock_is_released
    lock = tmp_path("boom", "lock")
    path = tmp_path("boom", "json")
    err = []
    boom = lambda { raise "boom" }
    r = PhomemoCLI::Runner.new(["--status", "--result", path], transport_factory: boom, stdout: [], stderr: err,
                               lock_path: lock)
    assert_equal 1, r.run
    j = read_json(path)
    assert_equal "unknown", j["error"]
    assert_equal "boom", j["hint"]
    assert_equal 1, j["exit_code"]
    assert_equal false, j["ok"]
    assert_equal "status", j["mode"]
    assert_equal 1, err.size
    again = PhomemoCLI::Lock.acquire(lock)
    assert_not_nil again
    again.release(now_ms: 0)
  end

  def test_an_unwritable_result_path_falls_back_to_stdout_and_keeps_the_exit_code
    out = []
    err = []
    t = fake(replies: ok_replies)
    code = runner(["--result", "/nonexistent-dir/result.json", fixture_path("stripes-600.pbm")], t,
                  out: out, err: err).run
    assert_equal 0, code
    assert_equal 1, out.size
    assert_equal true, JSON.parse(out[0])["ok"]
    assert_equal 1, err.size
    assert err[0].include?("/nonexistent-dir/result.json")
  end

  def test_an_unwritable_result_path_keeps_a_failure_exit_code_and_reports_both
    out = []
    err = []
    lock = tmp_path("unwritable", "lock")
    other = PhomemoCLI::Lock.acquire(lock)
    code = runner(["--status", "--result", "/nonexistent-dir/result.json"], lock: lock, out: out, err: err).run
    assert_equal 12, code
    assert_equal "busy", JSON.parse(out[0])["error"]
    assert_equal 2, err.size
    assert err[0].include?("/nonexistent-dir/result.json")
    assert err[1].include?("busy")
    other.release(now_ms: 0)
  end

  def test_an_exception_in_a_print_is_reported_in_print_mode
    path = tmp_path("boomprint", "json")
    boom = lambda { raise "boom" }
    r = PhomemoCLI::Runner.new(["--result", path, fixture_path("stripes-600.pbm")], transport_factory: boom,
                               stdout: [], stderr: [], lock_path: tmp_path("boomprint", "lock"))
    assert_equal 1, r.run
    j = read_json(path)
    assert_equal "print", j["mode"]
    assert_equal "unknown", j["error"]
  end

  def test_an_exception_without_a_result_path_goes_to_stdout_as_json
    out = []
    boom = lambda { raise "boom" }
    r = PhomemoCLI::Runner.new(["--status"], transport_factory: boom, stdout: out, stderr: [],
                               lock_path: tmp_path("boomout", "lock"))
    assert_equal 1, r.run
    assert_equal "unknown", JSON.parse(out[0])["error"]
  end

  def test_a_silent_printer_stops_a_print_with_exit_15_and_no_job_bytes
    path = tmp_path("silentprint", "json")
    t = fake(replies: {})
    code = runner(["--result", path, fixture_path("stripes-600.pbm")], t).run
    assert_equal 15, code
    r = read_json(path)
    assert_equal "status_unavailable", r["error"]
    assert_equal "print", r["mode"]
    assert_nil r["job"]
    assert_equal 0, t.job_writes.size
  end

  def test_a_missing_pbm_is_invalid_input_with_exit_2
    path = tmp_path("missing", "json")
    code = runner(["--result", path, "/nonexistent.pbm"]).run
    assert_equal 2, code
    r = read_json(path)
    assert_equal "invalid_input", r["error"]
    assert_equal 2, r["exit_code"]
    assert r["hint"].include?("/nonexistent.pbm")
  end

  def test_a_pbm_of_the_wrong_width_is_invalid_input
    pbm = pbm_file("wide", "P4\n100 10\n", 130)
    path = tmp_path("wide", "json")
    code = runner(["--result", path, pbm]).run
    assert_equal 2, code
    r = read_json(path)
    assert_equal "invalid_input", r["error"]
    assert r["hint"].include?("384")
  end

  def test_a_truncated_pbm_is_invalid_input_and_writes_no_job_bytes
    pbm = pbm_file("short", "P4\n384 10\n", 100)
    path = tmp_path("short", "json")
    lock = tmp_path("short", "lock")
    t = fake(replies: ok_replies)
    code = runner(["--result", path, pbm], t, lock: lock).run
    assert_equal 2, code
    assert_equal "invalid_input", read_json(path)["error"]
    assert read_json(path)["hint"].include?("truncated raster")
    assert_equal 0, t.job_writes.size
    assert_equal 0, t.writes.size
    assert_equal 0, t.connects.size
    assert_false File.exist?(lock)
  end

  def test_a_pbm_one_byte_short_is_rejected_before_connecting_and_an_exact_one_prints
    short = pbm_file("onebyte", "P4\n384 10\n", 479)
    t = fake(replies: ok_replies)
    assert_equal 2, runner(["--result", tmp_path("onebyte", "json"), short], t).run
    assert_equal 0, t.connects.size
    exact = pbm_file("exact", "P4\n384 10\n", 480)
    t = fake(replies: ok_replies)
    assert_equal 0, runner(["--result", tmp_path("exact", "json"), exact], t).run
    assert_equal 1, t.connects.size
  end

  def test_dry_run_with_a_bad_pbm_is_invalid_input
    pbm = pbm_file("drywide", "P4\n100 10\n", 130)
    path = tmp_path("drywide", "json")
    out = []
    code = runner(["--dry-run", "--result", path, pbm], out: out).run
    assert_equal 2, code
    r = read_json(path)
    assert_equal "dry_run", r["mode"]
    assert_equal "invalid_input", r["error"]
    assert_equal 0, out.size
  end

  def test_a_usage_error_is_exit_2_and_names_the_option
    path = tmp_path("usage", "json")
    err = []
    code = runner(["--result", path, "--density", "9", "a.pbm"], err: err).run
    assert_equal 2, code
    r = read_json(path)
    assert_equal "usage", r["error"]
    assert_equal 2, r["exit_code"]
    assert r["hint"].include?("--density")
    assert_equal 1, err.size
    assert err[0].include?("--density")
  end

  def test_a_usage_error_without_a_pbm
    err = []
    code = runner([], err: err).run
    assert_equal 2, code
    assert err[0].include?("PBM")
  end

  def test_a_vm_without_a_transport_reports_unknown
    path = tmp_path("nobt", "json")
    r = PhomemoCLI::Runner.new(["--status", "--result", path], transport_factory: nil, stdout: [], stderr: [],
                               lock_path: tmp_path("nobt", "lock"))
    assert_equal 1, r.run
    j = read_json(path)
    assert_equal "unknown", j["error"]
    assert j["hint"].include?("--dry-run")
  end

  def test_the_system_clock_and_sleeper_are_real
    clock = PhomemoCLI::SystemClock.new
    a = clock.now_ms
    PhomemoCLI::SystemSleeper.new.sleep_ms(30)
    assert clock.now_ms - a >= 20
  end
end
