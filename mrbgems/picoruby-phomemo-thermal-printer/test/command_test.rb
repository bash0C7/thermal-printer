class CommandTest < Picotest::Test
  def c; PhomemoThermalPrinter::Command; end

  def test_preamble_bytes_follow_the_ha_minimal_sequence_with_density
    assert_equal "\x1b\x40", c.initialize_printer
    assert_equal "\x1b\x61\x00", c.align(0)
    assert_equal "\x1f\x11\x02\x04", c.density(4)
  end

  def test_raster_header_writes_the_actual_row_count_little_endian
    assert_equal "\x1d\x76\x30\x00\x30\x00\x01\x00", c.raster_header(1)
    assert_equal "\x1d\x76\x30\x00\x30\x00\xff\x00", c.raster_header(255)
  end

  def test_raster_header_rejects_zero_and_more_than_255_rows
    assert_raise(ArgumentError) { c.raster_header(0) }
    assert_raise(ArgumentError) { c.raster_header(256) }
  end

  def test_density_accepts_only_1_to_5
    assert_raise(ArgumentError) { c.density(0) }
    assert_raise(ArgumentError) { c.density(6) }
  end

  def test_align_accepts_only_0_to_2
    assert_equal "\x1b\x61\x02", c.align(2)
    assert_raise(ArgumentError) { c.align(3) }
    assert_raise(ArgumentError) { c.align(-1) }
  end

  def test_feed_is_esc_d_n
    assert_equal "\x1b\x64\x03", c.feed(3)
  end

  def test_feed_accepts_only_0_to_255
    assert_raise(ArgumentError) { c.feed(-1) }
    assert_raise(ArgumentError) { c.feed(256) }
  end

  def test_builders_reject_non_integer_arguments
    assert_raise(ArgumentError) { c.density("4") }
    assert_raise(ArgumentError) { c.align(nil) }
    assert_raise(ArgumentError) { c.feed(1.5) }
    assert_raise(ArgumentError) { c.raster_header("1") }
    assert_raise(ArgumentError) { c.query(nil) }
  end

  def test_the_command_module_offers_no_raw_byte_entry_point
    assert_false c.respond_to?(:raw)
    assert_false c.respond_to?(:build)
    assert_false c.respond_to?(:bytes)
  end
end
