class JobTest < Picotest::Test
  class Blocks
    def initialize(list); @list = list; @i = 0; end
    def next_block; b = @list[@i]; @i += 1; b; end
  end

  def all_segments(job)
    out = []
    while (s = job.next_segment)
      out << s
    end
    out
  end

  def test_two_black_rows_match_the_research_example_plus_density
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[2, "\xff" * 96]]), density: 4)
    expected = "\x1b\x40\x1b\x61\x00\x1f\x11\x02\x04\x1d\x76\x30\x00\x30\x00\x02\x00" + "\xff" * 96 + "\x1b\x64\x03"
    assert_equal expected, all_segments(job).join
  end

  def test_every_segment_is_allowed
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[255, "\x00" * 48 * 255], [90, "\x00" * 48 * 90]]), density: 1)
    all_segments(job).each { |s| assert PhomemoThermalPrinter::Command.allowed?(s) }
  end

  def test_no_0x0a_substitution_happens
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[1, "\x0a" * 48]]), density: 4)
    assert all_segments(job).join.include?("\x0a" * 48)
  end

  def test_segments_are_preamble_then_one_per_block_then_postamble
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[255, "\x00" * 48 * 255], [90, "\x00" * 48 * 90]]), density: 4)
    segs = all_segments(job)
    assert_equal 4, segs.size
    assert_equal "\x1b\x40\x1b\x61\x00\x1f\x11\x02\x04", segs[0]
    assert_equal "\x1d\x76\x30\x00\x30\x00\xff\x00", segs[1].byteslice(0, 8)
    assert_equal 8 + 48 * 255, segs[1].bytesize
    assert_equal "\x1d\x76\x30\x00\x30\x00\x5a\x00", segs[2].byteslice(0, 8)
    assert_equal "\x1b\x64\x03", segs[3]
  end

  def test_feed_sets_the_postamble
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[1, "\x00" * 48]]), density: 4, feed: 6)
    assert_equal "\x1b\x64\x06", all_segments(job).last
  end

  def test_next_segment_is_nil_after_the_postamble
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[1, "\x00" * 48]]), density: 4)
    all_segments(job)
    assert_nil job.next_segment
    assert_nil job.next_segment
  end

  def test_rows_blocks_and_bytes_count_what_has_been_emitted
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[255, "\x00" * 48 * 255], [90, "\x00" * 48 * 90]]), density: 4)
    assert_equal 0, job.rows
    assert_equal 0, job.blocks
    assert_equal 0, job.bytes
    segs = all_segments(job)
    assert_equal 345, job.rows
    assert_equal 2, job.blocks
    assert_equal segs.join.bytesize, job.bytes
  end

  def test_density_outside_1_to_5_is_rejected_at_construction
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Job.new(Blocks.new([]), density: 0) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Job.new(Blocks.new([]), density: 6) }
  end

  def test_feed_outside_0_to_255_is_rejected_at_construction
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Job.new(Blocks.new([]), density: 4, feed: 256) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Job.new(Blocks.new([]), density: 4, feed: -1) }
  end

  def test_a_block_whose_bytes_do_not_match_its_rows_is_a_format_error
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[2, "\x00" * 95]]), density: 4)
    job.next_segment
    assert_raise(PhomemoThermalPrinter::FormatError) { job.next_segment }
  end

  def test_a_block_of_zero_or_more_than_255_rows_is_rejected
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[256, "\x00" * 48 * 256]]), density: 4)
    job.next_segment
    assert_raise(ArgumentError) { job.next_segment }
  end
end
