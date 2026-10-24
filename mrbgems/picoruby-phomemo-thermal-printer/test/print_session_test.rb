class PrintSessionTest < Picotest::Test
  class Blocks
    def initialize(list); @list = list; @i = 0; end
    def next_block; b = @list[@i]; @i += 1; b; end
  end

  class Segments
    attr_reader :rows, :blocks, :bytes

    def initialize(list, raise_at: nil)
      @list = list
      @i = 0
      @raise_at = raise_at
      @rows = 0
      @blocks = 0
      @bytes = 0
    end

    def next_segment
      raise PhomemoThermalPrinter::FormatError, "bad pixel data" if @raise_at == @i
      s = @list[@i]
      @i += 1
      s
    end
  end

  PREAMBLE = "\x1b\x40\x1b\x61\x00\x1f\x11\x02\x04"

  def fake(**opts)
    FakeTransport.new(FakeClock.new, **opts)
  end

  def session(t, interval: 20, chunk: 128)
    PhomemoThermalPrinter::PrintSession.new(t, clock: t.clock, sleeper: t.sleeper, interval: interval, chunk: chunk)
  end

  def blocks_for(rows, fill)
    list = []
    left = rows
    while left > 0
      n = left > 255 ? 255 : left
      list << [n, fill * (48 * n)]
      left -= n
    end
    list
  end

  def job(rows, fill = "\x00")
    PhomemoThermalPrinter::Job.new(Blocks.new(blocks_for(rows, fill)), density: 4)
  end

  def job_bytes(rows, fill = "\x00")
    j = job(rows, fill)
    out = ""
    while (s = j.next_segment)
      out << s
    end
    out
  end

  def boundaries(rows)
    out = []
    pos = 9
    left = rows
    while left > 0
      n = left > 255 ? 255 : left
      pos += 8 + 48 * n
      out << pos
      left -= n
    end
    out << pos + 3
    out
  end

  def boundary_at_or_after(rows, sent)
    list = boundaries(rows)
    i = 0
    while i < list.size
      return list[i] if list[i] >= sent
      i += 1
    end
    list[list.size - 1]
  end

  def pure_fill?(bytes)
    return true if bytes == "\x64\x00"
    i = 0
    while i < bytes.bytesize
      return false unless bytes.getbyte(i) == 0
      i += 1
    end
    true
  end

  def write_sizes(rows, chunk)
    t = fake(replies: ok_replies)
    session(t, chunk: chunk).run(job(rows, "\xff"))
    out = []
    list = t.job_writes
    i = 0
    while i < list.size
      out << list[i][1].bytesize
      i += 1
    end
    out
  end

  def at_event(event)
    lambda { |k| fake(replies: ok_replies, events_at_write: {k => event}) }
  end

  def at_poll_error
    lambda { |k| fake(replies: ok_replies, poll_error_at_write: k) }
  end

  def stops_cleanly_at_every_write(rows, chunk, error, build)
    full = job_bytes(rows, "\xff")
    sizes = write_sizes(rows, chunk)
    bad = []
    sent = 0
    k = 1
    while k <= sizes.size
      sent += sizes[k - 1]
      t = build.call(k)
      r = session(t, chunk: chunk).run(job(rows, "\xff"))
      stream = t.job_bytes
      bad << [k, "error"] unless r.error == error
      bad << [k, "not allowed"] unless PhomemoThermalPrinter::Command.allowed?(stream)
      bad << [k, "prefix"] unless stream.byteslice(0, sent) == full.byteslice(0, sent)
      bad << [k, "tail"] unless pure_fill?(stream.byteslice(sent, stream.bytesize - sent))
      bad << [k, "end"] unless stream.bytesize == boundary_at_or_after(rows, sent)
      k += 1
    end
    assert_equal [], bad
    sizes.size
  end

  def ok_replies
    {
      "\x1f\x11\x11" => "\x1a\x06\x89",
      "\x1f\x11\x12" => "\x1a\x05\x98",
      "\x1f\x11\x08" => "\x1a\x04\x53",
      "\x1f\x11\x13" => "\x1a\x03\xa8",
    }
  end

  def run_with(override, completion: "\x1a\x0f\x0c")
    t = fake(replies: ok_replies.merge(override), completion: completion)
    session(t).run(job(10))
  end

  def joined(writes)
    out = ""
    i = 0
    while i < writes.size
      out << writes[i][1]
      i += 1
    end
    out
  end

  def test_not_found_writes_nothing
    t = fake(found: false)
    r = session(t).run(job(10))
    assert_equal "not_found", r.error
    assert_equal false, r.ok
    assert_equal 0, t.writes.size
    assert_equal ["T02", 10_000], t.connects[0]
  end

  def test_a_t02_without_ff00_gets_nothing_at_all
    t = fake(gatt: {"service" => false, "write" => false, "notify" => false})
    r = session(t).run(job(10))
    assert_equal "wrong_device", r.error
    assert_equal 0, t.writes.size
    assert_equal 0, t.subscribes.size
  end

  def test_a_missing_notify_characteristic_is_also_the_wrong_device
    t = fake(gatt: {"service" => true, "write" => true, "notify" => false})
    r = session(t).run(job(10))
    assert_equal "wrong_device", r.error
    assert_equal 0, t.writes.size
  end

  def test_paper_out_in_the_precheck_sends_only_status_queries
    t = fake(replies: ok_replies.merge("\x1f\x11\x11" => "\x1a\x06\x88"))
    r = session(t).run(job(10))
    assert_equal "paper_out", r.error
    assert t.writes.size > 0
    t.writes.each { |w| assert_equal 3, w[1].bytesize }
  end

  def test_cover_open_overheat_and_empty_battery_also_stop_before_the_job
    assert_equal "cover_open", run_with({"\x1f\x11\x12" => "\x1a\x05\x99"}).error
    assert_equal "overheat", run_with({"\x1f\x11\x13" => "\x1a\x03\xa9"}).error
    assert_equal "low_battery", run_with({"\x1f\x11\x08" => "\x1a\x04\xa2"}).error
  end

  def test_the_precheck_asks_paper_cover_battery_and_temperature_in_that_order
    t = fake(replies: ok_replies)
    session(t).run(job(10))
    assert_equal ["\x1f\x11\x11", "\x1f\x11\x12", "\x1f\x11\x08", "\x1f\x11\x13"],
                 [t.query_writes[0][1], t.query_writes[1][1], t.query_writes[2][1], t.query_writes[3][1]]
    assert_equal 4, t.query_writes.size
  end

  def test_battery_at_6_percent_prints_and_at_5_percent_stops
    assert_equal true, run_with({"\x1f\x11\x08" => "\x1a\x04\x06"}).ok
    assert_equal "low_battery", run_with({"\x1f\x11\x08" => "\x1a\x04\x05"}).error
  end

  def test_battery_at_10_percent_prints_with_a_warning_and_11_does_not
    assert run_with({"\x1f\x11\x08" => "\x1a\x04\x0a"}).warnings.include?("battery_low")
    assert_equal [], run_with({"\x1f\x11\x08" => "\x1a\x04\x0b"}).warnings
    assert run_with({"\x1f\x11\x08" => "\x1a\x04\xa1"}).warnings.include?("battery_low")
  end

  def test_the_written_job_bytes_equal_the_job
    t = fake(replies: ok_replies)
    r = session(t).run(job(300))
    assert_equal true, r.ok
    assert_equal job_bytes(300), joined(t.job_writes)
    t.query_writes.each { |w| assert PhomemoThermalPrinter::Command.allowed?(w[1]) }
  end

  def test_no_chunk_exceeds_the_requested_size
    t = fake(replies: ok_replies)
    session(t, chunk: 100).run(job(300))
    t.job_writes.each { |w| assert w[1].bytesize <= 100 }
  end

  def test_chunks_are_spaced_by_the_interval
    t = fake(replies: ok_replies)
    session(t, interval: 20).run(job(300))
    data = t.job_writes
    assert data.size > 2
    i = 1
    while i < data.size
      assert data[i][0] - data[i - 1][0] >= 20
      i += 1
    end
  end

  def test_the_first_job_chunk_also_waits_for_the_interval_after_the_last_query
    t = fake(replies: ok_replies)
    session(t, interval: 100).run(job(10))
    assert t.job_writes[0][0] - t.query_writes[3][0] >= 100
  end

  def test_max_write_from_the_printer_caps_the_chunk
    t = fake(replies: ok_replies, connect_notifications: ["\x01\x01", "\x02\x60\x00"])
    r = session(t, chunk: 182).run(job(300))
    t.job_writes.each { |w| assert w[1].bytesize <= 96 }
    assert_equal 96, r.job["chunk_size"]
    assert_equal 96, r.notify["max_write"]
  end

  def test_a_max_write_below_20_is_raised_to_20
    t = fake(replies: ok_replies, connect_notifications: ["\x02\x0a\x00"])
    r = session(t, chunk: 128).run(job(10))
    assert_equal true, r.ok
    assert_equal 20, r.job["chunk_size"]
    t.job_writes.each { |w| assert w[1].bytesize <= 20 }
  end

  def test_a_max_write_above_the_requested_chunk_does_not_raise_it
    t = fake(replies: ok_replies)
    r = session(t, chunk: 128).run(job(10))
    assert_equal 128, r.job["chunk_size"]
    assert_equal 182, r.notify["max_write"]
  end

  def test_completion_ends_the_wait_after_at_least_2000ms
    t = fake(replies: ok_replies, completion_after_ms: 500)
    r = session(t).run(job(48))
    assert_equal "notified", r.completion_state
    assert r.after_send_ms >= 2000
    assert r.after_send_ms < 2100
    assert r.notify["events"].include?("1a0f0c")
  end

  def test_a_late_completion_ends_the_wait_when_it_arrives
    t = fake(replies: ok_replies, completion_after_ms: 2500)
    r = session(t).run(job(48))
    assert_equal "notified", r.completion_state
    assert r.after_send_ms >= 2500
  end

  def test_without_completion_the_wait_ends_at_the_cap_with_a_warning
    t = fake(replies: ok_replies, completion: nil)
    r = session(t).run(job(480))
    assert_equal true, r.ok
    assert r.warnings.include?("completion_unconfirmed")
    assert_equal "unconfirmed", r.completion_state
    assert r.after_send_ms >= 12_000
    assert r.after_send_ms < 12_100
  end

  def test_the_cap_is_never_below_2000ms
    t = fake(replies: ok_replies, completion: nil)
    r = session(t).run(job(1))
    assert r.after_send_ms >= 2000
    assert r.after_send_ms < 2100
  end

  def test_silence_in_the_precheck_stops_with_status_unavailable_before_any_job_byte
    t = fake(replies: {}, completion: nil)
    r = session(t).run(job(48))
    assert_equal "status_unavailable", r.error
    assert_equal false, r.ok
    assert_equal 0, t.job_writes.size
    t.writes.each { |w| assert_equal 3, w[1].bytesize }
    assert_nil r.status
    assert_nil r.job
    assert_equal [], r.warnings
    assert r.hint.include?("accept the macOS pairing prompt")
    assert r.hint.include?("run again")
  end

  def test_silence_waits_6000ms_rewrites_the_cccd_and_asks_again
    t = fake(replies: {}, completion: nil)
    session(t).run(job(10))
    assert_equal 2, t.subscribes.size
    assert t.subscribes[1] - t.subscribes[0] >= 6000
    assert_equal 8, t.query_writes.size
  end

  def test_pairing_that_completes_during_the_wait_recovers_the_status
    t = fake(replies: ok_replies, notify_from_subscribe: 2)
    r = session(t).run(job(10))
    assert_equal true, r.ok
    assert_equal [], r.warnings
    assert_equal 2, t.subscribes.size
    assert_equal 83, r.status["battery"]
    assert_equal "ok", r.status["paper"]
  end

  def test_a_precheck_with_some_replies_prints_with_status_partial_and_does_not_resubscribe
    t = fake(replies: {"\x1f\x11\x11" => "\x1a\x06\x89", "\x1f\x11\x12" => "\x1a\x05\x98"})
    r = session(t).run(job(10))
    assert_equal true, r.ok
    assert_equal ["status_partial"], r.warnings
    assert_equal 1, t.subscribes.size
    assert_equal 4, t.query_writes.size
    assert_equal "ok", r.status["paper"]
    assert_nil r.status["battery"]
  end

  def test_failure_and_cancel_notifications_are_errors
    assert_equal "print_failed", run_with({}, completion: "\x1a\x0f\x01").error
    assert_equal "canceled", run_with({}, completion: "\x1a\x0b\xb8").error
  end

  def test_disconnect_while_sending_stops_writing
    t = fake(replies: ok_replies, disconnect_at_write: 5)
    r = session(t).run(job(300))
    assert_equal "disconnected", r.error
    assert_equal 5, t.job_writes.size
    assert r.hint.include?("Turn the printer off and on before the next print")
  end

  def test_disconnect_during_the_precheck_writes_no_job_bytes
    t = fake(replies: ok_replies, disconnect_at_poll: 2)
    r = session(t).run(job(300))
    assert_equal "disconnected", r.error
    assert_equal 0, t.job_writes.size
    assert_false r.hint.include?("off and on")
  end

  def test_a_precheck_with_one_missing_reply_is_status_partial_and_a_full_one_is_not
    t = fake(replies: ok_replies.merge("\x1f\x11\x13" => nil))
    r = session(t).run(job(10))
    assert_equal ["status_partial"], r.warnings
    assert_equal [], session(fake(replies: ok_replies)).run(job(10)).warnings
  end

  def test_the_precheck_queries_are_spaced_by_the_poll_interval
    t = fake(replies: ok_replies)
    session(t).run(job(10))
    w = t.query_writes
    assert_equal 4, w.size
    i = 1
    while i < w.size
      assert w[i][0] - w[i - 1][0] >= 20
      i += 1
    end
  end

  def test_acks_fewer_than_chunks_add_the_ack_mismatch_warning
    t = fake(replies: ok_replies, acks: false)
    r = session(t).run(job(300))
    assert_equal true, r.ok
    assert r.warnings.include?("ack_mismatch")
    assert_equal 0, r.notify["acks"]
  end

  def test_matching_acks_add_no_warning
    r = session(fake(replies: ok_replies)).run(job(300))
    assert_equal [], r.warnings
  end

  def test_a_completion_that_arrives_mid_send_does_not_end_the_wait
    t = fake(replies: ok_replies, events_at_write: {2 => "\x1a\x0f\x0c"}, completion: nil)
    r = session(t).run(job(480))
    assert_equal true, r.ok
    assert_equal "unconfirmed", r.completion_state
    assert r.warnings.include?("completion_unconfirmed")
    assert r.after_send_ms >= 12_000
  end

  def test_only_a_completion_after_the_last_write_ends_the_wait
    t = fake(replies: ok_replies, events_at_write: {2 => "\x1a\x0f\x0c"}, completion_after_ms: 2500)
    r = session(t).run(job(48))
    assert_equal "notified", r.completion_state
    assert r.after_send_ms >= 2500
    assert_equal [], r.warnings
  end

  def test_cover_open_in_the_first_block_pads_it_with_zeros_and_sends_no_feed
    t = fake(replies: ok_replies, events_at_write: {3 => "\x1a\x05\x99"})
    r = session(t).run(job(300, "\xff"))
    assert_equal "cover_open", r.error
    stream = t.job_bytes
    assert_equal 9 + 8 + 255 * 48, stream.bytesize
    assert PhomemoThermalPrinter::Command.allowed?(stream)
    assert_equal "\xff" * (3 * 128 - 17), stream.byteslice(17, 3 * 128 - 17)
    assert_equal "\x00" * (stream.bytesize - 3 * 128), stream.byteslice(3 * 128, stream.bytesize - 3 * 128)
    assert_false stream.end_with?("\x1b\x64\x03")
    assert_equal t.job_writes.size, r.job["chunks"]
  end

  def test_padding_goes_through_the_chunk_size_the_interval_and_the_printer_limit
    t = fake(replies: ok_replies, events_at_write: {3 => "\x1a\x05\x99"},
             connect_notifications: ["\x01\x01", "\x02\x60\x00"])
    session(t, interval: 50, chunk: 182).run(job(300, "\xff"))
    data = t.job_writes
    assert data.size > 3
    i = 0
    while i < data.size
      assert data[i][1].bytesize <= 96
      assert data[i][0] - data[i - 1][0] >= 50 if i > 0
      i += 1
    end
  end

  def test_a_link_lost_while_padding_is_disconnected_with_the_power_cycle_hint
    t = fake(replies: ok_replies, events_at_write: {3 => "\x1a\x05\x99"}, disconnect_at_write: 6)
    r = session(t).run(job(300, "\xff"))
    assert_equal "disconnected", r.error
    assert_equal 6, t.job_writes.size
    assert r.hint.include?("Turn the printer off and on before the next print")
  end

  def test_a_stop_on_a_block_boundary_adds_nothing
    t = fake(replies: ok_replies, events_at_write: {103 => "\x1a\x05\x99"})
    r = session(t, chunk: 119).run(job(255, "\xff"))
    assert_equal "cover_open", r.error
    assert_equal 103, t.job_writes.size
    assert_equal 9 + 8 + 255 * 48, t.job_bytes.bytesize
    assert PhomemoThermalPrinter::Command.allowed?(t.job_bytes)
  end

  def test_a_chunk_boundary_that_would_cut_a_header_moves_in_front_of_it
    sizes = write_sizes(300, 61)
    assert_equal 57, sizes[200]
    sizes.each { |s| assert s <= 61 }
    t = fake(replies: ok_replies, events_at_write: {201 => "\x1a\x05\x99"})
    r = session(t, chunk: 61).run(job(300, "\xff"))
    assert_equal "cover_open", r.error
    assert_equal 9 + 8 + 255 * 48, t.job_bytes.bytesize
    assert_equal 201, t.job_writes.size
  end

  def test_a_feed_cut_by_a_chunk_boundary_is_completed_as_a_zero_line_feed
    t = fake(replies: ok_replies, events_at_write: {229 => "\x1a\x05\x99"})
    r = session(t, chunk: 63).run(job(300, "\xff"))
    assert_equal "cover_open", r.error
    stream = t.job_bytes
    assert_equal 14428, stream.bytesize
    assert stream.end_with?("\x1b\x64\x00")
    assert PhomemoThermalPrinter::Command.allowed?(stream)
  end

  def raster(rows, fill)
    PhomemoThermalPrinter::Command.raster_header(rows) + fill * (48 * rows)
  end

  def test_a_disallowed_segment_after_a_block_still_completes_the_declared_block
    big = raster(255, "\xff")
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE, big, "\x1f\x11\x20"]))
    assert_equal "print_failed", r.error
    stream = t.job_bytes
    assert_equal PREAMBLE.bytesize + big.bytesize, stream.bytesize
    assert_equal "\x00" * 97, stream.byteslice(95 * 128, 97)
    assert PhomemoThermalPrinter::Command.allowed?(stream)
  end

  def test_a_format_error_after_a_block_still_completes_the_declared_block
    big = raster(255, "\xff")
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE, big], raise_at: 2))
    assert_equal "invalid_input", r.error
    stream = t.job_bytes
    assert_equal PREAMBLE.bytesize + big.bytesize, stream.bytesize
    assert PhomemoThermalPrinter::Command.allowed?(stream)
  end

  def test_small_blocks_that_never_filled_a_chunk_leave_the_sent_one_complete
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE, raster(3, "\xff"), raster(1, "\xff")], raise_at: 3))
    assert_equal "invalid_input", r.error
    stream = t.job_bytes
    assert_equal PREAMBLE.bytesize + 8 + 3 * 48, stream.bytesize
    assert PhomemoThermalPrinter::Command.allowed?(stream)
  end

  def test_nothing_on_the_wire_means_nothing_is_padded
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE, raster(1, "\xff")], raise_at: 2))
    assert_equal "invalid_input", r.error
    assert_equal 0, t.job_writes.size
  end

  def test_cover_open_at_every_write_of_a_300_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(300, 128, "cover_open", at_event("\x1a\x05\x99"))
    assert_equal 113, n
  end

  def test_print_failed_at_every_write_of_a_300_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(300, 128, "print_failed", at_event("\x1a\x0f\x01"))
    assert_equal 113, n
  end

  def test_canceled_at_every_write_of_a_300_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(300, 128, "canceled", at_event("\x1a\x0b\xb8"))
    assert_equal 113, n
  end

  def test_cover_open_at_every_write_of_a_600_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(600, 128, "cover_open", at_event("\x1a\x05\x99"))
    assert_equal 226, n
  end

  def test_print_failed_at_every_write_of_a_600_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(600, 128, "print_failed", at_event("\x1a\x0f\x01"))
    assert_equal 226, n
  end

  def test_paper_out_and_overheat_at_every_write_of_a_300_row_job_leave_a_valid_stream
    stops_cleanly_at_every_write(300, 128, "paper_out", at_event("\x1a\x06\x88"))
    stops_cleanly_at_every_write(300, 128, "overheat", at_event("\x1a\x03\xa9"))
  end

  def test_a_chunk_size_that_meets_the_second_header_leaves_a_valid_stream_at_every_write
    n = stops_cleanly_at_every_write(300, 61, "cover_open", at_event("\x1a\x05\x99"))
    assert_equal 237, n
  end

  def test_a_chunk_size_that_cuts_the_feed_leaves_a_valid_stream_at_every_write
    n = stops_cleanly_at_every_write(300, 63, "cover_open", at_event("\x1a\x05\x99"))
    assert_equal 230, n
  end

  def test_the_smallest_chunk_leaves_a_valid_stream_at_every_write_of_a_small_job
    n = stops_cleanly_at_every_write(7, 20, "cover_open", at_event("\x1a\x05\x99"))
    assert_equal 18, n
  end

  def test_a_transport_exception_at_every_write_of_a_300_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(300, 128, "unknown", at_poll_error)
    assert_equal 113, n
  end

  def test_a_transport_exception_at_every_write_with_header_and_feed_cuts_leaves_a_valid_stream
    stops_cleanly_at_every_write(300, 61, "unknown", at_poll_error)
    stops_cleanly_at_every_write(300, 63, "unknown", at_poll_error)
  end

  def test_a_transport_exception_at_every_write_of_a_600_row_job_leaves_a_valid_stream
    n = stops_cleanly_at_every_write(600, 128, "unknown", at_poll_error)
    assert_equal 226, n
  end

  def test_a_transport_exception_stops_with_the_power_cycle_hint_and_the_message
    t = fake(replies: ok_replies, poll_error_at_write: 3)
    r = session(t).run(job(300, "\xff"))
    assert_equal "unknown", r.error
    assert r.hint.include?("poll failed")
    assert r.hint.include?("Turn the printer off and on before the next print")
    assert_equal 9 + 8 + 255 * 48, t.job_bytes.bytesize
    assert_equal 1, t.disconnects
  end

  def test_a_transport_exception_while_waiting_for_completion_is_unknown_with_the_job_report
    t = fake(replies: ok_replies, poll_error_ms_after_write: 100)
    r = session(t).run(job(300, "\xff"))
    assert_equal "unknown", r.error
    assert_equal 300, r.job["rows"]
    assert_equal 14428, t.job_bytes.bytesize
  end

  def test_a_transport_exception_that_keeps_happening_while_padding_is_disconnected
    t = fake(replies: ok_replies, poll_error_at_write: 3, poll_error_repeats: true)
    r = session(t).run(job(300, "\xff"))
    assert_equal "disconnected", r.error
    assert_equal 4, t.job_writes.size
    assert r.hint.include?("Turn the printer off and on before the next print")
    assert_equal 1, t.disconnects
  end

  def test_a_288_row_job_waits_for_the_last_block_to_print_before_finishing
    t = fake(replies: ok_replies, completion_after_ms: 500)
    r = session(t).run(job(288))
    assert_equal "notified", r.completion_state
    assert r.after_send_ms >= 5312
    assert r.after_send_ms < 5400
  end

  def test_a_96_row_job_still_finishes_after_2000ms
    t = fake(replies: ok_replies, completion_after_ms: 500)
    r = session(t).run(job(96))
    assert_equal "notified", r.completion_state
    assert r.after_send_ms >= 2000
    assert r.after_send_ms < 2100
  end

  def test_a_missing_paper_reply_stops_before_any_job_byte
    t = fake(replies: ok_replies.merge("\x1f\x11\x11" => nil))
    r = session(t).run(job(10))
    assert_equal "status_unavailable", r.error
    assert_equal 0, t.job_writes.size
    assert_nil r.job
    assert r.hint.include?("accept the macOS pairing prompt")
  end

  def test_a_missing_cover_reply_stops_before_any_job_byte
    t = fake(replies: ok_replies.merge("\x1f\x11\x12" => nil))
    r = session(t).run(job(10))
    assert_equal "status_unavailable", r.error
    assert_equal 0, t.job_writes.size
    assert_nil r.job
  end

  def test_a_missing_battery_reply_prints_with_status_partial
    t = fake(replies: ok_replies.merge("\x1f\x11\x08" => nil))
    r = session(t).run(job(10))
    assert_equal true, r.ok
    assert_equal ["status_partial"], r.warnings
    assert t.job_writes.size > 0
  end

  def test_a_missing_temperature_reply_prints_with_status_partial
    t = fake(replies: ok_replies.merge("\x1f\x11\x13" => nil))
    r = session(t).run(job(10))
    assert_equal true, r.ok
    assert_equal ["status_partial"], r.warnings
  end

  def test_cover_opened_while_sending_stops_writing
    t = fake(replies: ok_replies, events_at_write: {3 => "\x1a\x05\x99"})
    r = session(t).run(job(300))
    assert_equal "cover_open", r.error
    assert t.job_writes.size > 3
    assert_equal 9 + 8 + 255 * 48, t.job_bytes.bytesize
    assert r.notify["events"].include?("1a0599")
  end

  def test_paper_pulled_and_overheat_while_sending_stop_writing
    t = fake(replies: ok_replies, events_at_write: {2 => "\x1a\x06\x88"})
    assert_equal "paper_out", session(t).run(job(300)).error
    t = fake(replies: ok_replies, events_at_write: {2 => "\x1a\x03\xa9"})
    assert_equal "overheat", session(t).run(job(300)).error
  end

  def test_a_segment_that_is_not_allowed_never_reaches_the_transport
    bad = "\x1f\x11\x20"
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE, bad, "\x1b\x64\x03"]))
    assert_equal "print_failed", r.error
    assert_equal false, joined(t.writes).include?(bad)
    assert_equal 4, t.writes.size
  end

  def test_an_unlisted_first_segment_aborts_before_any_job_byte
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new(["\x1b\x4e\x04\x01", PREAMBLE]))
    assert_equal "print_failed", r.error
    assert_equal 0, t.job_writes.size
    t.writes.each { |w| assert_equal 3, w[1].bytesize }
  end

  def test_a_segment_that_stops_short_of_a_whole_command_is_not_allowed
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE, "\x1d\x76\x30\x00\x30\x00\x02\x00" + "\xff" * 95]))
    assert_equal "print_failed", r.error
    assert_equal 4, t.writes.size
  end

  def test_a_malformed_block_in_the_middle_of_the_job_is_invalid_input
    t = fake(replies: ok_replies)
    r = session(t).run(Segments.new([PREAMBLE], raise_at: 1))
    assert_equal "invalid_input", r.error
    assert_equal "bad pixel data", r.hint
  end

  def test_acks_count_the_job_writes_without_the_subscription_and_query_acks
    t = fake(replies: ok_replies)
    r = session(t).run(job(300))
    assert_equal t.job_writes.size, r.notify["acks"]
    assert_equal r.job["chunks"], r.notify["acks"]
  end

  def test_unknown_notifications_are_recorded_and_not_errors
    t = fake(replies: ok_replies)
    r = session(t).run(job(10))
    assert_equal true, r.ok
    assert r.notify["events"].include?("1a3b0440000000")
  end

  def test_concatenated_notifications_are_split
    t = fake(replies: {"\x1f\x11\x11" => "\x1a\x06\x88\x1a\x05\x98"},
             connect_notifications: ["\x01\x01\x02\xb6\x00\x1a\x3b\x04\x40\x00\x00\x00"])
    r = session(t).run(job(10))
    assert_equal "paper_out", r.error
    assert_equal "closed", r.status["cover"]
    assert_equal 182, r.notify["max_write"]
  end

  def test_a_reply_split_across_two_notifications_is_joined
    t = fake(replies: ok_replies.merge("\x1f\x11\x08" => ["\x1a", "\x04\x53"]))
    r = session(t).run(job(10))
    assert_equal 83, r.status["battery"]
  end

  def test_the_job_report_counts_rows_blocks_bytes_and_chunks
    t = fake(replies: ok_replies)
    j = job(300)
    r = session(t, interval: 20, chunk: 128).run(j)
    assert_equal 300, r.job["rows"]
    assert_equal 2, r.job["blocks"]
    assert_equal job_bytes(300).bytesize, r.job["bytes"]
    assert_equal t.job_writes.size, r.job["chunks"]
    assert_equal 128, r.job["chunk_size"]
    assert_equal 20, r.job["interval_ms"]
    assert_equal 4, r.job["density"]
  end

  def test_elapsed_ms_runs_from_the_start_to_the_end
    t = fake(found: false)
    r = session(t).run(job(10))
    assert_equal 10_000, r.elapsed_ms
  end

  def test_the_session_always_disconnects_after_connecting
    t = fake(replies: ok_replies)
    session(t).run(job(10))
    assert_equal 1, t.disconnects
    t = fake(replies: ok_replies.merge("\x1f\x11\x11" => "\x1a\x06\x88"))
    session(t).run(job(10))
    assert_equal 1, t.disconnects
    t = fake(found: false)
    session(t).run(job(10))
    assert_equal 0, t.disconnects
  end

  def test_the_status_of_a_print_comes_from_the_precheck_replies
    t = fake(replies: ok_replies)
    r = session(t).run(job(10))
    assert_equal 83, r.status["battery"]
    assert_equal "ok", r.status["paper"]
    assert_equal "closed", r.status["cover"]
    assert_equal "normal", r.status["temperature"]
  end
end

class ResultTest < Picotest::Test
  def test_a_failure_carries_the_hint_for_its_error
    r = PhomemoThermalPrinter::Result.failure("print", "not_found", elapsed_ms: 10_012)
    h = r.to_h(exit_code: 10)
    assert_equal false, h["ok"]
    assert_equal "not_found", h["error"]
    assert_equal 10, h["exit_code"]
    assert_equal "T02 was not found. Press the power button to wake it, disconnect the official app, and check that Bluetooth access is allowed for this app.", h["hint"]
    assert_nil h["status"]
    assert_nil h["job"]
    assert_nil h["notify"]
    assert_nil h["completion"]
    assert_equal 10_012, h["elapsed_ms"]
  end

  def test_the_hash_has_the_contract_keys_in_order
    h = PhomemoThermalPrinter::Result.new("status").to_h(exit_code: 0)
    assert_equal ["version", "mode", "ok", "error", "exit_code", "hint", "warnings", "status", "job",
                  "notify", "completion", "elapsed_ms"], h.keys
    assert_equal 1, h["version"]
    assert_equal "status", h["mode"]
    assert_equal true, h["ok"]
    assert_equal [], h["warnings"]
  end

  def test_an_explicit_hint_wins_over_the_table
    r = PhomemoThermalPrinter::Result.failure("print", "invalid_input", hint: "width is not 384")
    assert_equal "width is not 384", r.hint
  end

  def test_a_warning_is_added_once
    r = PhomemoThermalPrinter::Result.new("print")
    r.add_warning("status_unavailable")
    r.add_warning("status_unavailable")
    assert_equal ["status_unavailable"], r.warnings
  end

  def test_completion_appears_in_the_hash_once_set
    r = PhomemoThermalPrinter::Result.new("print")
    r.complete("notified", 2310)
    h = r.to_h(exit_code: 0)
    assert_equal({"state" => "notified", "after_send_ms" => 2310}, h["completion"])
  end
end
