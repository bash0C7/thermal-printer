class StatusTest < Picotest::Test
  def decode(s)
    PhomemoThermalPrinter::StatusDecoder.new.feed(s)
  end

  def test_the_t02_log_from_jef_decodes_in_order
    assert_equal [[:ack], [:max_write, 182]], decode("\x01\x01\x02\xb6\x00")
    assert_equal [[:paper, :ok], [:cover, :closed]], decode("\x1a\x06\x89\x1a\x05\x98")
    assert_equal [[:battery, 83]], decode("\x1a\x04\x53")
    assert_equal [[:firmware, "3.0.7"]], decode("\x1a\x07\x03\x00\x07")
    assert_equal [[:serial, "Q114E48T2580915"]], decode("\x1a\x08Q114E48T2580915")
    assert_equal [[:print_complete]], decode("\x1a\x0f\x0c")
  end

  def test_the_three_notifications_observed_on_subscribe_are_decoded_without_error
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [[:ack]], d.feed("\x01\x01")
    assert_equal [[:max_write, 182]], d.feed("\x02\xb6\x00")
    assert_equal [[:unknown, "1a3b0440000000"]], d.feed("\x1a\x3b\x04\x40\x00\x00\x00")
  end

  def test_the_observed_3b_notification_does_not_swallow_the_next_reply
    assert_equal [[:unknown, "1a3b0440000000"], [:paper, :ok]],
                 decode("\x1a\x3b\x04\x40\x00\x00\x00\x1a\x06\x89")
  end

  def test_max_write_is_a_little_endian_16_bit_value
    assert_equal [[:max_write, 256]], decode("\x02\x00\x01")
  end

  def test_majority_meanings_win_over_minority_readings
    assert_equal [[:cover, :open]], decode("\x1a\x05\x99")
    assert_equal [[:paper, :out]], decode("\x1a\x06\x88")
    assert_equal [[:temperature, :overheat]], decode("\x1a\x03\xa9")
    assert_equal [[:temperature, :normal]], decode("\x1a\x03\xa8")
  end

  def test_auto_off_carries_the_raw_value
    assert_equal [[:auto_off, 12]], decode("\x1a\x09\x0c")
  end

  def test_battery_special_values_map_to_percent
    assert_equal [[:battery, 10], [:battery, 5], [:battery, 3], [:battery, 0]],
                 decode("\x1a\x04\xa1\x1a\x04\xa2\x1a\x04\xa3\x1a\x04\xa4")
  end

  def test_a_battery_value_that_is_neither_a_percent_nor_a_special_value_is_unknown
    assert_equal [[:unknown, "1a04a5"]], decode("\x1a\x04\xa5")
  end

  def test_a_reply_split_across_two_notifications_is_joined
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [], d.feed("\x1a\x07\x03")
    assert_equal [[:firmware, "3.0.7"]], d.feed("\x00\x07")
  end

  def test_a_serial_split_in_the_middle_is_joined
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [], d.feed("\x1a\x08Q114E4")
    assert_equal [[:serial, "Q114E48T2580915"]], d.feed("8T2580915")
  end

  def test_a_notification_that_ends_after_the_1a_byte_waits_for_the_type
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [[:ack]], d.feed("\x01\x01\x1a")
    assert_equal [[:paper, :ok]], d.feed("\x06\x89")
  end

  def test_a_lone_01_or_a_short_02_waits_for_the_rest
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [], d.feed("\x01")
    assert_equal [[:ack]], d.feed("\x01\x02\xb6")
    assert_equal [[:max_write, 182]], d.feed("\x00")
  end

  def test_several_replies_in_one_notification_decode_in_order
    assert_equal [[:paper, :ok], [:cover, :closed], [:battery, 83], [:print_complete]],
                 decode("\x1a\x06\x89\x1a\x05\x98\x1a\x04\x53\x1a\x0f\x0c")
  end

  def test_an_empty_notification_yields_nothing
    assert_equal [], decode("")
  end

  def test_failure_and_cancel_are_distinct_events
    assert_equal [[:print_failed, 1]], decode("\x1a\x0f\x01")
    assert_equal [[:canceled]], decode("\x1a\x0b\xb8")
  end

  def test_known_length_unknown_meaning_types_are_skipped_as_unknown
    assert_equal [[:unknown, "1a3b0102030405"], [:paper, :ok]], decode("\x1a\x3b\x01\x02\x03\x04\x05\x1a\x06\x89")
  end

  def test_a_known_type_with_an_unlisted_value_is_unknown
    assert_equal [[:unknown, "1a0577"], [:unknown, "1a0b01"]], decode("\x1a\x05\x77\x1a\x0b\x01")
  end

  def test_an_unlisted_1a_type_becomes_unknown_and_resets_the_buffer
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [[:unknown, "1a7f0102"]], d.feed("\x1a\x7f\x01\x02")
    assert_equal [[:paper, :ok]], d.feed("\x1a\x06\x89")
  end

  def test_an_unparseable_byte_becomes_unknown_and_resets_the_buffer
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [[:unknown, "ee0102"]], d.feed("\xee\x01\x02")
    assert_equal [[:paper, :ok]], d.feed("\x1a\x06\x89")
  end
end
