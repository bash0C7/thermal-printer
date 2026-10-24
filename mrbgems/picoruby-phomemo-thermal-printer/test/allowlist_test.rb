class AllowlistTest < Picotest::Test
  KNOWN = [0x07, 0x08, 0x09, 0x0e, 0x11, 0x12, 0x13]

  def test_status_query_can_be_built_only_for_the_seven_known_opcodes
    op = 0
    while op <= 0xff
      if KNOWN.include?(op)
        assert_equal "\x1f\x11" + [op].pack("C"), PhomemoThermalPrinter::Command.query(op)
      else
        assert_raise(ArgumentError) { PhomemoThermalPrinter::Command.query(op) }
      end
      op += 1
    end
  end

  def test_status_query_rejects_out_of_byte_range_opcodes
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Command.query(-1) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Command.query(0x100) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Command.query(0x113) }
  end

  def test_allowed_rejects_the_commands_the_research_marks_dangerous
    ["\x1f\x11\x14", "\x1f\x11\x38", "\x1f\x11\x63", "\x1b\x4e\x04\x01", "\x1b\x37\x07\x80\x02",
     "\x1d\x7c\x01", "\x1d\x67\x6e", "SSSGETSN\r\n", "\x1f\x11\x02\x00", "\x1f\x11\x02\x06",
     "\x1b\x61\x03", "\x1d\x76\x30\x01\x30\x00\x01\x00" + "\x00" * 48].each do |seg|
      assert_false PhomemoThermalPrinter::Command.allowed?(seg)
    end
  end

  def test_allowed_rejects_empty_truncated_and_non_string_segments
    c = PhomemoThermalPrinter::Command
    assert_false c.allowed?("")
    assert_false c.allowed?(nil)
    assert_false c.allowed?("\x1b")
    assert_false c.allowed?("\x1b\x61")
    assert_false c.allowed?("\x1f\x11")
    assert_false c.allowed?("\x1f\x11\x02")
    assert_false c.allowed?("\x1d\x76\x30\x00\x30\x00\x01")
  end

  def test_allowed_rejects_raster_headers_with_a_bad_width_or_row_count
    c = PhomemoThermalPrinter::Command
    assert_false c.allowed?("\x1d\x76\x30\x00\x31\x00\x01\x00" + "\x00" * 48)
    assert_false c.allowed?("\x1d\x76\x30\x00\x30\x01\x01\x00" + "\x00" * 48)
    assert_false c.allowed?("\x1d\x76\x30\x00\x30\x00\x00\x00")
    assert_false c.allowed?("\x1d\x76\x30\x00\x30\x00\x00\x01" + "\x00" * 48)
    assert_false c.allowed?("\x1d\x76\x30\x00\x30\x00\x01\x01" + "\x00" * 48)
  end

  def test_allowed_requires_exactly_48_bytes_per_declared_row
    header = PhomemoThermalPrinter::Command.raster_header(2)
    assert PhomemoThermalPrinter::Command.allowed?(header + "\x00" * 96)
    assert_false PhomemoThermalPrinter::Command.allowed?(header + "\x00" * 95)
    assert_false PhomemoThermalPrinter::Command.allowed?(header + "\x00" * 97)
  end

  def test_allowed_does_not_read_raster_data_as_commands
    c = PhomemoThermalPrinter::Command
    data = "\x1f\x11\x14" + "\xff" * 45
    assert c.allowed?(c.raster_header(1) + data)
    assert_false c.allowed?(c.raster_header(1) + data + "\x1f\x11\x14")
  end

  def test_allowed_accepts_a_concatenation_of_allowed_commands_only
    c = PhomemoThermalPrinter::Command
    pre = c.initialize_printer + c.align(0) + c.density(4)
    assert c.allowed?(pre)
    assert c.allowed?(pre + c.raster_header(1) + "\x00" * 48 + c.feed(3))
    assert_false c.allowed?(pre + "\x1f\x11\x14")
    assert_false c.allowed?(pre + "\x00")
  end

  def test_every_builder_output_is_allowed
    c = PhomemoThermalPrinter::Command
    [c.initialize_printer, c.align(0), c.align(2), c.density(1), c.density(5),
     c.feed(0), c.feed(255), c.query(0x13)].each { |seg| assert c.allowed?(seg) }
  end

  def test_every_query_opcode_output_is_allowed_and_every_other_1f_11_byte_is_not
    c = PhomemoThermalPrinter::Command
    op = 0
    while op <= 0xff
      seg = "\x1f\x11" + [op].pack("C")
      if KNOWN.include?(op)
        assert c.allowed?(seg)
      else
        assert_false c.allowed?(seg)
      end
      op += 1
    end
  end

  def test_every_density_and_align_byte_outside_the_allowlist_is_rejected
    c = PhomemoThermalPrinter::Command
    n = 0
    while n <= 0xff
      density_ok = 1 <= n && n <= 5
      align_ok = n <= 2
      assert_equal density_ok, c.allowed?("\x1f\x11\x02" + [n].pack("C"))
      assert_equal align_ok, c.allowed?("\x1b\x61" + [n].pack("C"))
      assert c.allowed?("\x1b\x64" + [n].pack("C"))
      n += 1
    end
  end
end
