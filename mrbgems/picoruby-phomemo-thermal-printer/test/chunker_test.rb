class ChunkerTest < Picotest::Test
  def test_chunks_never_exceed_the_size_and_preserve_bytes
    ch = PhomemoThermalPrinter::Chunker.new(128)
    out = ch.push("a" * 300) + ch.push("b" * 10)
    last = ch.flush
    out << last if last
    out.each { |c| assert c.bytesize <= 128 }
    assert_equal "a" * 300 + "b" * 10, out.join
  end

  def test_the_printer_reported_max_write_lowers_the_size
    ch = PhomemoThermalPrinter::Chunker.new(182)
    ch.limit(96)
    ch.push("x" * 500).each { |c| assert c.bytesize <= 96 }
  end

  def test_size_outside_20_to_182_is_rejected
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Chunker.new(183) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Chunker.new(19) }
  end

  def test_only_full_chunks_are_returned_and_the_rest_waits_for_flush
    ch = PhomemoThermalPrinter::Chunker.new(100)
    assert_equal [], ch.push("a" * 99)
    out = ch.push("b" * 150)
    assert_equal 2, out.size
    assert_equal 100, out[0].bytesize
    assert_equal 100, out[1].bytesize
    assert_equal "b" * 49, ch.flush
  end

  def test_flush_is_nil_when_nothing_is_left
    ch = PhomemoThermalPrinter::Chunker.new(64)
    assert_nil ch.flush
    ch.push("a" * 64)
    assert_nil ch.flush
  end

  def test_flush_empties_the_buffer
    ch = PhomemoThermalPrinter::Chunker.new(64)
    ch.push("a" * 10)
    assert_equal "a" * 10, ch.flush
    assert_nil ch.flush
  end

  def test_chunks_span_segment_boundaries
    ch = PhomemoThermalPrinter::Chunker.new(20)
    out = ch.push("a" * 15) + ch.push("b" * 15)
    assert_equal ["a" * 15 + "b" * 5], out
    assert_equal "b" * 10, ch.flush
  end

  def test_binary_bytes_are_counted_per_byte_not_per_character
    ch = PhomemoThermalPrinter::Chunker.new(20)
    seg = "\xff\xfe\x00\x0a\x80" * 10
    out = ch.push(seg)
    last = ch.flush
    out << last if last
    out.each { |c| assert c.bytesize <= 20 }
    assert_equal seg, out.join
  end

  def test_limit_does_not_raise_the_size
    ch = PhomemoThermalPrinter::Chunker.new(64)
    ch.limit(182)
    ch.push("x" * 200).each { |c| assert c.bytesize <= 64 }
  end

  def test_limit_applies_to_bytes_already_buffered
    ch = PhomemoThermalPrinter::Chunker.new(182)
    assert_equal [], ch.push("y" * 150)
    ch.limit(50)
    out = ch.push("z")
    assert_equal 3, out.size
    out.each { |c| assert c.bytesize <= 50 }
    assert_equal "y" * 150 + "z", out.join + ch.flush.to_s
  end

  HEADER = "\x1d\x76\x30\x00\x30\x00\x02\x00"

  def drain(ch, segments)
    out = []
    i = 0
    while i < segments.size
      out.concat(ch.push(segments[i]))
      i += 1
    end
    last = ch.flush
    out << last if last
    out
  end

  def test_a_boundary_inside_a_raster_header_moves_in_front_of_it
    ch = PhomemoThermalPrinter::Chunker.new(20)
    out = drain(ch, ["a" * 15, HEADER + "b" * 96])
    assert_equal "a" * 15, out[0]
    assert_equal HEADER + "b" * 12, out[1]
    assert_equal "a" * 15 + HEADER + "b" * 96, out.join
    out.each { |c| assert c.bytesize <= 20 }
  end

  def test_a_boundary_right_after_the_header_or_right_before_it_is_not_moved
    ch = PhomemoThermalPrinter::Chunker.new(20)
    out = drain(ch, ["a" * 12, HEADER + "b" * 40])
    assert_equal ["a" * 12 + HEADER, "b" * 20, "b" * 20], out
    ch = PhomemoThermalPrinter::Chunker.new(20)
    out = drain(ch, ["a" * 20, HEADER + "b" * 12])
    assert_equal ["a" * 20, HEADER + "b" * 12], out
  end

  def test_no_boundary_falls_inside_any_header_for_any_size_and_offset
    sizes = [20, 21, 27, 61, 100, 128, 182]
    sizes.each do |size|
      pre = 0
      while pre < 30
        ch = PhomemoThermalPrinter::Chunker.new(size)
        segments = ["p" * pre, HEADER + "q" * 150, "r" * 3, HEADER + "s" * 90, "\x1b\x64\x03"]
        out = drain(ch, segments)
        assert_equal segments.join, out.join
        starts = [pre, pre + 8 + 150 + 3]
        pos = 0
        out.each do |c|
          pos += c.bytesize
          starts.each { |h| assert_false(pos > h && pos < h + 8) }
          assert c.bytesize <= size
        end
        pre += 1
      end
    end
  end

  def test_a_header_waiting_in_the_buffer_is_protected_after_the_size_shrinks
    ch = PhomemoThermalPrinter::Chunker.new(182)
    assert_equal [], ch.push("a" * 100)
    assert_equal [], ch.push(HEADER + "b" * 10)
    ch.limit(104)
    out = ch.push("c" * 5)
    assert_equal ["a" * 100], out
    assert_equal HEADER + "b" * 10 + "c" * 5, ch.flush
  end

  def test_limit_below_20_is_rejected
    ch = PhomemoThermalPrinter::Chunker.new(128)
    assert_raise(ArgumentError) { ch.limit(19) }
  end
end
