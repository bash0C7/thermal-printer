require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../tools/make_test_pbm"

class MakeTestPbmTest < Minitest::Test
  TOOL = File.expand_path("../../tools/make_test_pbm.rb", __dir__)
  PATTERNS = %w[topline ruler density chunk grid]

  def header(data)
    head = data.b[/\AP4\n\d+ \d+\n/n]
    rows = head.split("\n")[1].split(" ")[1].to_i
    [head, rows]
  end

  def row(data, index)
    head, = header(data)
    data.b.byteslice(head.bytesize + index * 48, 48)
  end

  def pixel(data, x, y)
    (row(data, y).getbyte(x / 8) >> (7 - x % 8)) & 1
  end

  def black_dots(bytes)
    bytes.unpack1("B*").count("1")
  end

  def test_every_pattern_is_a_384_wide_p4
    (PATTERNS + ["label"]).each do |pat|
      data = pat == "label" ? MakeTestPbm.render(pat, "T02 D4") : MakeTestPbm.render(pat)
      assert data.start_with?("P4\n384 "), pat
      head, rows = header(data)
      assert_equal rows * 48, data.bytesize - head.bytesize, pat
    end
  end

  def test_output_is_binary_and_deterministic
    PATTERNS.each do |pat|
      first = MakeTestPbm.render(pat)
      assert_equal Encoding::BINARY, first.encoding
      assert_equal first, MakeTestPbm.render(pat)
    end
  end

  def test_topline_starts_with_three_black_rows
    data = MakeTestPbm.render("topline")
    head, = header(data)
    assert_equal "\xff".b * (48 * 3), data.byteslice(head.bytesize, 48 * 3)
    assert_equal "\x00".b * 48, row(data, 3)
  end

  def test_topline_has_a_tick_every_millimetre
    data = MakeTestPbm.render("topline")
    assert_equal 96, header(data)[1]
    assert_equal "\xff".b * 8, row(data, 8).byteslice(0, 8)
    assert_equal "\x00".b * 40, row(data, 8).byteslice(8, 40)
    assert_equal "\x00".b * 48, row(data, 9)
    assert_equal "\xff".b * 24, row(data, 80).byteslice(0, 24)
    assert_equal "\x00".b * 24, row(data, 80).byteslice(24, 24)
    assert_equal "\xff".b * 8, row(data, 88).byteslice(0, 8)
  end

  def grid
    @grid ||= MakeTestPbm.render("grid")
  end

  def test_grid_is_133_rows_with_a_black_top_bar_and_six_millimetres_of_white_at_the_end
    assert_equal 133, header(grid)[1]
    3.times { |r| assert_equal "\xff".b * 48, row(grid, r) }
    assert_equal "\xff".b * 48, row(grid, 84)
    (85...133).each { |r| assert_equal "\x00".b * 48, row(grid, r), "r=#{r}" }
  end

  def test_grid_has_a_two_dot_bar_at_each_end_of_the_head
    (3...85).each do |y|
      [0, 1, 382, 383].each { |x| assert_equal 1, pixel(grid, x, y), "x=#{x} y=#{y}" }
    end
    assert_equal 0, pixel(grid, 2, 10)
    assert_equal 0, pixel(grid, 381, 10)
  end

  def test_grid_has_dotted_lines_every_millimetre_in_both_directions
    assert_equal 1, pixel(grid, 8, 5)
    assert_equal 0, pixel(grid, 8, 6)
    assert_equal 1, pixel(grid, 4, 11)
    assert_equal 0, pixel(grid, 5, 11)
  end

  def test_grid_has_solid_lines_every_five_millimetres
    [10, 14, 30].each do |y|
      assert_equal [0, 1, 1, 0], [39, 40, 41, 42].map { |x| pixel(grid, x, y) }, "y=#{y}"
    end
    assert_equal "\xff".b * 48, row(grid, 43)
  end

  def test_grid_has_four_dot_wide_lines_every_ten_millimetres
    assert_equal [1, 1, 1, 1, 0], (80..84).map { |x| pixel(grid, x, 10) }
    assert_equal "\xff".b * 48, row(grid, 83)
    assert_equal "\xff".b * 48, row(grid, 84)
  end

  def test_grid_marks_the_head_centre_with_a_four_dot_line
    assert_equal [0, 1, 1, 1, 1, 0], (189..194).map { |x| pixel(grid, x, 30) }
  end

  def test_grid_has_a_downward_arrow_under_the_top_bar_pointing_at_the_centre_line
    assert_equal [0, 1, 1, 0], [183, 184, 199, 202].map { |x| pixel(grid, x, 5) }
    assert_equal [1, 1], [191, 192].map { |x| pixel(grid, x, 12) }
    assert_equal [0, 1, 1, 0], [186, 187, 196, 197].map { |x| pixel(grid, x, 8) }
  end

  def test_grid_has_an_upward_arrow_above_the_bottom_bar_pointing_at_the_centre_line
    assert_equal [0, 1, 1, 0], [183, 184, 199, 202].map { |x| pixel(grid, x, 82) }
    assert_equal [1, 1], [191, 192].map { |x| pixel(grid, x, 75) }
    assert_equal [0, 1, 1, 0], [186, 187, 196, 197].map { |x| pixel(grid, x, 79) }
  end

  def test_ruler_is_20mm
    _, rows = header(MakeTestPbm.render("ruler"))
    assert_equal 160, rows
  end

  def test_ruler_has_short_and_long_ticks_and_an_end_mark
    data = MakeTestPbm.render("ruler")
    assert_equal "\xff".b * 8, row(data, 8).byteslice(0, 8)
    assert_equal "\x00".b * 40, row(data, 8).byteslice(8, 40)
    assert_equal "\xff".b * 24, row(data, 80).byteslice(0, 24)
    assert_equal "\x00".b * 48, row(data, 79)
    assert_equal "\xff".b * 48, row(data, 159)
    assert_equal "\xff".b * 48, row(data, 156)
    assert_equal "\x00".b * 48, row(data, 155)
  end

  def test_density_has_sixteen_bands_each_darker_than_the_last
    data = MakeTestPbm.render("density")
    assert_equal 16 * 8, header(data)[1]
    counts = (0...16).map do |band|
      (0...8).sum { |r| black_dots(row(data, band * 8 + r)) }
    end
    assert_equal (1..16).map { |k| 384 * 8 * k / 16 }, counts
  end

  def test_density_bands_use_an_ordered_dither
    data = MakeTestPbm.render("density")
    assert_equal row(data, 0), row(data, 4)
    assert_equal row(data, 1), row(data, 5)
    assert_equal "\xff".b * 48, row(data, 15 * 8)
  end

  def test_chunk_is_a_one_millimetre_grid_15mm_long
    data = MakeTestPbm.render("chunk")
    assert_equal 120, header(data)[1]
    assert_equal "\xff".b * 48, row(data, 0)
    assert_equal "\x80".b * 48, row(data, 1)
    assert_equal "\xff".b * 48, row(data, 8)
    assert_equal "\xff".b * 48, row(data, 112)
  end

  def test_label_draws_the_glyph_with_a_scale_of_three
    data = MakeTestPbm.render("label", "A")
    assert_equal 0, pixel(data, 8, 2)
    assert_equal 0, pixel(data, 10, 2)
    assert_equal 1, pixel(data, 11, 2)
    assert_equal 1, pixel(data, 19, 4)
    assert_equal 0, pixel(data, 20, 2)
    assert_equal 1, pixel(data, 8, 2 + 3 * 3)
    assert_equal 1, pixel(data, 19, 2 + 3 * 3 + 2)
    assert_equal 0, pixel(data, 8 + 18 + 3, 2)
  end

  def test_label_band_is_26_rows_ending_in_a_rule
    data = MakeTestPbm.render("label", "A")
    assert_equal 26, header(data)[1]
    assert_equal "\x00".b * 48, row(data, 24)
    assert_equal "\xff".b * 48, row(data, 25)
  end

  def test_label_text_changes_the_picture
    refute_equal MakeTestPbm.render("label", "D3"), MakeTestPbm.render("label", "D4")
  end

  def test_label_accepts_digits_letters_equals_hyphen_and_space_and_upcases
    assert_equal MakeTestPbm.render("label", "T02 D=4-X"), MakeTestPbm.render("label", "t02 d=4-x")
  end

  def test_label_rejects_unsupported_characters_and_overlong_text
    assert_raises(ArgumentError) { MakeTestPbm.render("label", "A/B") }
    assert_raises(ArgumentError) { MakeTestPbm.render("label", "A" * 21) }
    assert_raises(ArgumentError) { MakeTestPbm.render("label") }
    MakeTestPbm.render("label", "A" * 20)
  end

  def test_label_option_prepends_a_band_to_any_pattern
    band = MakeTestPbm.render("label", "RULER")
    bare = MakeTestPbm.render("ruler")
    labelled = MakeTestPbm.render("ruler", label: "RULER")
    band_rows = header(band)[1]
    assert_equal band_rows + 160, header(labelled)[1]
    head, = header(labelled)
    assert_equal band.byteslice(band.index("\n", 3) + 1..), labelled.byteslice(head.bytesize, band_rows * 48)
    assert_equal bare.byteslice(header(bare)[0].bytesize..), labelled.byteslice(head.bytesize + band_rows * 48..)
  end

  def test_unknown_pattern_is_rejected
    assert_raises(ArgumentError) { MakeTestPbm.render("nope") }
    assert_raises(ArgumentError) { MakeTestPbm.render("blocks") }
  end

  def test_cli_writes_the_same_bytes_as_render
    Dir.mktmpdir do |dir|
      out = File.join(dir, "ruler.pbm")
      _, status = Open3.capture2e(RbConfig.ruby, TOOL, "ruler", out)
      assert status.success?
      assert_equal MakeTestPbm.render("ruler"), File.binread(out)
    end
  end

  def test_cli_joins_label_words_and_takes_a_label_option
    Dir.mktmpdir do |dir|
      out = File.join(dir, "label.pbm")
      _, status = Open3.capture2e(RbConfig.ruby, TOOL, "label", out, "T02", "D=4")
      assert status.success?
      assert_equal MakeTestPbm.render("label", "T02 D=4"), File.binread(out)

      out = File.join(dir, "topline.pbm")
      _, status = Open3.capture2e(RbConfig.ruby, TOOL, "topline", out, "--label", "D4")
      assert status.success?
      assert_equal MakeTestPbm.render("topline", label: "D4"), File.binread(out)
    end
  end

  def test_cli_exits_2_with_usage_for_bad_arguments
    Dir.mktmpdir do |dir|
      out = File.join(dir, "x.pbm")
      stderr, status = Open3.capture2e(RbConfig.ruby, TOOL, "nope", out)
      assert_equal 2, status.exitstatus
      assert_match(/usage/i, stderr)
      refute File.exist?(out)
      _, status = Open3.capture2e(RbConfig.ruby, TOOL)
      assert_equal 2, status.exitstatus
    end
  end
end
