class StatusSessionTest < Picotest::Test
  def fake(**opts)
    FakeTransport.new(FakeClock.new, **opts)
  end

  def query(t)
    PhomemoThermalPrinter::StatusSession.new(t, clock: t.clock, sleeper: t.sleeper).query
  end

  def all_replies
    {
      "\x1f\x11\x08" => "\x1a\x04\x53",
      "\x1f\x11\x11" => "\x1a\x06\x89",
      "\x1f\x11\x12" => "\x1a\x05\x98",
      "\x1f\x11\x13" => "\x1a\x03\xa8",
      "\x1f\x11\x07" => "\x1a\x07\x03\x00\x07",
      "\x1f\x11\x09" => "\x1a\x08Q114E48T2580915",
      "\x1f\x11\x0e" => "\x1a\x09\x0c",
    }
  end

  def test_status_asks_the_seven_known_queries_in_order
    t = fake(replies: all_replies)
    r = query(t)
    assert_equal ["\x1f\x11\x08", "\x1f\x11\x11", "\x1f\x11\x12", "\x1f\x11\x13",
                  "\x1f\x11\x07", "\x1f\x11\x09", "\x1f\x11\x0e"],
                 [t.writes[0][1], t.writes[1][1], t.writes[2][1], t.writes[3][1],
                  t.writes[4][1], t.writes[5][1], t.writes[6][1]]
    assert_equal 7, t.writes.size
    assert_equal 83, r.status["battery"]
    assert_equal "3.0.7", r.status["firmware"]
  end

  def test_every_status_field_is_reported
    r = query(fake(replies: all_replies))
    assert_equal true, r.ok
    assert_equal({"battery" => 83, "paper" => "ok", "cover" => "closed", "temperature" => "normal",
                  "firmware" => "3.0.7", "serial" => "Q114E48T2580915", "auto_off" => 12}, r.status)
  end

  def test_a_status_query_never_writes_anything_but_the_seven_queries
    t = fake(replies: all_replies)
    query(t)
    t.writes.each { |w| assert PhomemoThermalPrinter::Command.allowed?(w[1]) }
    t.writes.each { |w| assert_equal 3, w[1].bytesize }
  end

  def test_no_reply_at_all_is_status_unavailable
    t = fake(replies: {})
    r = query(t)
    assert_equal "status_unavailable", r.error
    assert_equal false, r.ok
    assert_nil r.status
  end

  def test_silence_waits_6000ms_rewrites_the_cccd_and_asks_again
    t = fake(replies: {})
    query(t)
    assert_equal 2, t.subscribes.size
    assert t.subscribes[1] - t.subscribes[0] >= 6000
    assert_equal 14, t.writes.size
  end

  def test_pairing_that_completes_during_the_wait_recovers_the_status
    t = fake(replies: all_replies, notify_from_subscribe: 2)
    r = query(t)
    assert_equal true, r.ok
    assert_equal 2, t.subscribes.size
    assert_equal 83, r.status["battery"]
  end

  def test_some_missing_replies_are_not_an_error
    t = fake(replies: {"\x1f\x11\x08" => "\x1a\x04\x53"})
    r = query(t)
    assert_equal true, r.ok
    assert_equal 83, r.status["battery"]
    assert_nil r.status["firmware"]
  end

  def test_the_unknown_notification_on_subscribe_is_recorded_not_an_error
    r = query(fake(replies: all_replies))
    assert_equal true, r.ok
    assert_equal ["1a3b0440000000"], r.notify["events"]
    assert_equal 182, r.notify["max_write"]
    assert_equal 0, r.notify["acks"]
  end

  def test_the_replies_in_one_concatenated_notification_are_all_decoded
    t = fake(replies: {"\x1f\x11\x08" => "\x1a\x04\x53\x1a\x06\x89\x1a\x05\x98\x1a\x03\xa8"})
    r = query(t)
    assert_equal 83, r.status["battery"]
    assert_equal "ok", r.status["paper"]
    assert_equal "closed", r.status["cover"]
    assert_equal "normal", r.status["temperature"]
  end

  def test_not_found_and_wrong_device_write_nothing
    t = fake(found: false)
    assert_equal "not_found", query(t).error
    assert_equal 0, t.writes.size
    t = fake(gatt: {"service" => true, "write" => true, "notify" => false})
    assert_equal "wrong_device", query(t).error
    assert_equal 0, t.writes.size
  end

  def test_a_disconnect_while_asking_is_reported
    t = fake(replies: all_replies, disconnect_at_poll: 2)
    assert_equal "disconnected", query(t).error
  end

  def test_the_result_is_a_status_mode_hash_without_a_job
    h = query(fake(replies: all_replies)).to_h(exit_code: 0)
    assert_equal "status", h["mode"]
    assert_equal true, h["ok"]
    assert_nil h["job"]
    assert_nil h["completion"]
    assert_equal [], h["warnings"]
    assert h["elapsed_ms"] > 0
  end

  def test_a_low_battery_is_a_warning_in_status_mode_not_an_error
    r = query(fake(replies: all_replies.merge("\x1f\x11\x08" => "\x1a\x04\x08")))
    assert_equal true, r.ok
    assert_equal ["battery_low"], r.warnings
  end

  def test_the_session_disconnects_after_connecting
    t = fake(replies: all_replies)
    query(t)
    assert_equal 1, t.disconnects
  end
end
