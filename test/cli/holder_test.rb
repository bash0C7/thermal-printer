require 'json'

class HolderTest < Picotest::Test
  def ok_replies
    {
      "\x1f\x11\x11" => "\x1a\x06\x89",
      "\x1f\x11\x12" => "\x1a\x05\x98",
      "\x1f\x11\x08" => "\x1a\x04\x53",
      "\x1f\x11\x13" => "\x1a\x03\xa8",
    }
  end

  def setup
    @prefix = "/tmp/phomemo-cli-holdertest-#{Machine.board_millis}-"
    @clock = FakeClock.new
    @built = []
  end

  def teardown
    names = ["job.pbm", "job.pbm.tmp", "result.json", "result.json.tmp", "close", "state", "state.tmp"]
    i = 0
    while i < names.size
      path = @prefix + names[i]
      File.delete(path) if File.exist?(path)
      i += 1
    end
  end

  def transport(**opts)
    FakeTransport.new(@clock, replies: ok_replies, **opts)
  end

  def holder(list)
    built = @built
    factory = lambda do
      t = list[built.size] || list[list.size - 1]
      built << t
      t
    end
    sleeper = list[0].sleeper
    PhomemoCLI::Holder.new(@prefix, transport_factory: factory, clock: @clock, sleeper: sleeper)
  end

  def put(name, bytes)
    File.open(@prefix + name, "w") { |f| f.write(bytes) }
  end

  def put_job(rows)
    put("job.pbm", "P4\n384 #{rows}\n" + ("\x00" * (48 * rows)))
  end

  def written_state
    File.open(@prefix + "state", "r") { |f| f.read }
  end

  def written_result
    JSON.parse(File.open(@prefix + "result.json", "r") { |f| f.read })
  end

  def test_the_first_step_links_and_says_so
    t = transport
    h = holder([t])
    assert_true h.step
    assert_equal "linked", written_state
    assert_equal 1, t.connects.size
    assert_equal 0, t.disconnects
  end

  def test_a_job_on_the_held_link_prints_without_a_new_connect
    t = transport
    h = holder([t])
    h.step
    put_job(10)
    h.step
    assert_true written_result["ok"]
    assert_equal 10, written_result["job"]["rows"]
    assert_equal 1, t.connects.size
    assert_false File.exist?(@prefix + "job.pbm")
    assert_equal "linked", written_state
  end

  def test_the_job_is_printed_at_the_density_it_was_given
    t = transport
    h = PhomemoCLI::Holder.new(@prefix, transport_factory: lambda { t }, density: 2, clock: @clock, sleeper: t.sleeper)
    h.step
    put_job(10)
    h.step
    assert_equal 2, written_result["job"]["density"]
  end

  def test_a_printer_that_is_not_found_leaves_the_holder_unlinked_until_the_retry
    off = transport(found: false)
    h = holder([off])
    h.step
    assert_equal "unlinked", written_state
    h.step
    assert_equal 1, @built.size
    @clock.advance(PhomemoCLI::Holder::RETRY_MS)
    h.step
    assert_equal 2, @built.size
  end

  def test_a_lost_link_is_noticed_and_relinked_on_a_fresh_transport
    first = transport
    second = transport
    h = holder([first, second])
    h.step
    first.lose_link
    h.step
    assert_equal "unlinked", written_state
    @clock.advance(PhomemoCLI::Holder::RETRY_MS)
    h.step
    assert_equal "linked", written_state
    assert_equal 1, second.connects.size
  end

  def test_a_job_while_unlinked_still_tries_to_print_on_a_fresh_transport
    off = transport(found: false)
    h = holder([off])
    h.step
    put_job(10)
    h.step
    assert_equal "not_found", written_result["error"]
    assert_equal 10, written_result["exit_code"]
    assert_false File.exist?(@prefix + "job.pbm")
  end

  def test_a_failed_job_leaves_the_holder_unlinked
    t = FakeTransport.new(@clock, replies: ok_replies.merge("\x1f\x11\x11" => "\x1a\x06\x88"))
    h = holder([t])
    h.step
    put_job(10)
    h.step
    assert_equal "paper_out", written_result["error"]
    assert_equal "unlinked", written_state
  end

  def test_a_truncated_job_is_invalid_input_and_writes_no_job_bytes
    t = transport
    h = holder([t])
    h.step
    put("job.pbm", "P4\n384 10\n" + ("\x00" * 47))
    writes = t.writes.size
    h.step
    assert_equal "invalid_input", written_result["error"]
    assert_equal writes, t.writes.size
    assert_equal "linked", written_state
  end

  def test_close_disconnects_and_ends_the_loop
    t = transport
    h = holder([t])
    h.step
    put("close", "")
    assert_false h.step
    assert_equal 1, t.disconnects
    assert_equal "closed", written_state
    assert_false File.exist?(@prefix + "close")
  end

  def test_run_steps_until_close
    t = transport
    h = holder([t])
    put("close", "")
    assert_equal "closed", h.run
  end
end
