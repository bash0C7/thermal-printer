class PbmReaderTest < Picotest::Test
  class ChunkIO
    attr_reader :max_read
    def initialize(s); @s = s; @pos = 0; @max_read = 0; end
    def read(n)
      @max_read = n if n > @max_read
      return nil if @pos >= @s.bytesize
      r = @s.byteslice(@pos, n); @pos += r.bytesize; r
    end
  end

  def pbm(rows, comment: false)
    head = comment ? "P4\n# made by test\n384 #{rows}\n" : "P4\n384 #{rows}\n"
    body = ""
    i = 0
    while i < rows
      body << ((i % 2 == 0) ? "\xff" : "\x00") * 48
      i += 1
    end
    head + body
  end

  def test_600_rows_come_out_as_255_255_90
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(600)))
    assert_equal 384, r.width
    assert_equal 600, r.height
    sizes = []
    while (b = r.next_block)
      assert_equal b[0] * 48, b[1].bytesize
      sizes << b[0]
    end
    assert_equal [255, 255, 90], sizes
  end

  def test_blocks_concatenate_to_the_original_raster
    src = pbm(600, comment: true)
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(src))
    out = ""
    while (b = r.next_block)
      out << b[1]
    end
    assert_equal src.byteslice(src.bytesize - 600 * 48, 600 * 48), out
  end

  def test_reads_at_most_one_block_at_a_time
    io = ChunkIO.new(pbm(600))
    r = PhomemoThermalPrinter::PbmReader.new(io)
    while r.next_block; end
    assert io.max_read <= 255 * 48
  end

  def test_max_rows_caps_the_block_size
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(10)), max_rows: 4)
    sizes = []
    while (b = r.next_block)
      sizes << b[0]
    end
    assert_equal [4, 4, 2], sizes
  end

  def test_next_block_stays_nil_after_the_last_block
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(3)))
    assert_equal 3, r.next_block[0]
    assert_equal nil, r.next_block
    assert_equal nil, r.next_block
  end

  def test_header_with_a_comment_line_is_skipped
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(5, comment: true)))
    assert_equal 384, r.width
    assert_equal 5, r.height
  end

  def test_width_other_than_384_is_a_format_error
    assert_raise(PhomemoThermalPrinter::FormatError) do
      PhomemoThermalPrinter::PbmReader.new(ChunkIO.new("P4\n383 1\n" + "\x00" * 48))
    end
  end

  def test_truncated_raster_is_a_format_error
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(10).byteslice(0, 9 + 48 * 9)))
    assert_raise(PhomemoThermalPrinter::FormatError) { while r.next_block; end }
  end

  def test_p1_ascii_pbm_is_a_format_error
    assert_raise(PhomemoThermalPrinter::FormatError) do
      PhomemoThermalPrinter::PbmReader.new(ChunkIO.new("P1\n384 1\n"))
    end
  end

  def test_empty_input_is_a_format_error
    assert_raise(PhomemoThermalPrinter::FormatError) do
      PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(""))
    end
  end

  def test_zero_height_is_a_format_error
    assert_raise(PhomemoThermalPrinter::FormatError) do
      PhomemoThermalPrinter::PbmReader.new(ChunkIO.new("P4\n384 0\n"))
    end
  end

  def test_a_file_as_long_as_the_header_plus_every_row_is_complete
    src = pbm(10)
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(src))
    assert_true r.complete_in?(src.bytesize)
    assert_true r.complete_in?(src.bytesize + 7)
    assert_false r.complete_in?(src.bytesize - 1)
    assert_false r.complete_in?(10)
  end

  def test_header_comments_count_toward_the_header_length
    src = pbm(10, comment: true)
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(src))
    assert_true r.complete_in?(src.bytesize)
    assert_false r.complete_in?(src.bytesize - 1)
  end

  def test_the_length_check_does_not_consume_the_raster
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(3)))
    r.complete_in?(1000)
    assert_equal 3, r.next_block[0]
  end

  def test_the_stripes_fixture_reads_through_a_binary_file
    f = File.open("mrbgems/picoruby-phomemo-thermal-printer/test/fixtures/stripes-600.pbm", "rb")
    r = PhomemoThermalPrinter::PbmReader.new(f)
    assert_equal 384, r.width
    assert_equal 600, r.height
    sizes = []
    first = nil
    while (b = r.next_block)
      first ||= b[1]
      sizes << b[0]
    end
    f.close
    assert_equal [255, 255, 90], sizes
    assert_equal 255 * 48, first.bytesize
    assert_equal 255, first.getbyte(0)
    assert_equal 0, first.getbyte(48)
    assert_equal 255, first.getbyte(96)
  end
end
