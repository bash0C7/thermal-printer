require "minitest/autorun"
require "open3"
require "tmpdir"
require "zlib"
require_relative "../../tools/make_test_pbm"

class DryRunPngTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  BIN = File.join(ROOT, "bin", "phomemo-print")
  VM = ENV["PHOMEMO_PICORUBY"] || File.join(ROOT, "vendor", "R2P2-darwin", "build", "host", "bin", "picoruby")
  STRIPES = File.join(ROOT, "mrbgems", "picoruby-phomemo-thermal-printer", "test", "fixtures", "stripes-600.pbm")
  SIGNATURE = "\x89PNG\r\n\x1a\n".b

  def setup
    skip "product VM not built (run rake vm:build): #{VM}" unless File.executable?(VM)
  end

  def tall_pbm(rows)
    body = Array.new(rows) { |r| Array.new(48) { |j| (r * 7 + j * 13) & 0xff }.pack("C*") }.join
    "P4\n384 #{rows}\n".b + body
  end

  def pbm_rows(data)
    head = data.b[/\AP4\n\d+ \d+\n/n]
    height = head.split("\n")[1].split(" ")[1].to_i
    body = data.b.byteslice(head.bytesize, height * 48)
    Array.new(height) { |r| body.byteslice(r * 48, 48) }
  end

  def run_png(pbm_data)
    Dir.mktmpdir do |dir|
      pbm = File.join(dir, "in.pbm")
      png = File.join(dir, "out.png")
      File.binwrite(pbm, pbm_data)
      out, err, status = Open3.capture3({ "PHOMEMO_PICORUBY" => VM }, BIN, "--dry-run", "--png", png, pbm)
      assert status.success?, "exit #{status.exitstatus}: #{err}"
      assert File.exist?(png), "no PNG written: #{err}"
      refute File.exist?("#{png}.tmp")
      yield out, File.binread(png)
    end
  end

  def chunks(png)
    assert_equal SIGNATURE, png.byteslice(0, 8)
    list = []
    pos = 8
    while pos < png.bytesize
      len = png.byteslice(pos, 4).unpack1("N")
      type = png.byteslice(pos + 4, 4)
      data = png.byteslice(pos + 8, len)
      crc = png.byteslice(pos + 8 + len, 4).unpack1("N")
      assert_equal Zlib.crc32(type + data), crc, "CRC of #{type}"
      list << [type, data]
      pos += 12 + len
    end
    assert_equal pos, png.bytesize
    list
  end

  def assert_png_matches(pbm_data)
    rows = pbm_rows(pbm_data)
    run_png(pbm_data) do |out, png|
      assert_match(/\Atotal chunks=\d+ bytes=\d+ rows=#{rows.size}\z/, out.lines.last.chomp)
      list = chunks(png)
      assert_equal %w[IHDR PLTE IDAT IEND], list.map(&:first)
      width, height, depth, color, compression, filter, interlace = list[0][1].unpack("NNCCCCC")
      assert_equal [384, rows.size, 1, 3, 0, 0, 0], [width, height, depth, color, compression, filter, interlace]
      assert_equal "\xff\xff\xff\x00\x00\x00".b, list[1][1]
      raw = Zlib::Inflate.inflate(list[2][1])
      assert_equal rows.size * 49, raw.bytesize
      rows.each_with_index do |row, r|
        assert_equal 0, raw.getbyte(r * 49), "filter byte of row #{r}"
        assert_equal row, raw.byteslice(r * 49 + 1, 48), "row #{r}"
      end
    end
  end

  def test_the_stripes_fixture_round_trips_through_the_png
    assert_png_matches(File.binread(STRIPES))
  end

  def test_the_ruler_pattern_round_trips_through_the_png
    assert_png_matches(MakeTestPbm.render("ruler"))
  end

  def test_an_image_whose_raw_size_crosses_65535_bytes_round_trips
    assert_png_matches(tall_pbm(1400))
  end

  def test_the_chunk_listing_does_not_change_with_png
    Dir.mktmpdir do |dir|
      png = File.join(dir, "out.png")
      plain, = Open3.capture3({ "PHOMEMO_PICORUBY" => VM }, BIN, "--dry-run", STRIPES)
      with, = Open3.capture3({ "PHOMEMO_PICORUBY" => VM }, BIN, "--dry-run", "--png", png, STRIPES)
      assert_equal plain, with
    end
  end

  def test_png_without_dry_run_is_a_usage_error
    Dir.mktmpdir do |dir|
      png = File.join(dir, "out.png")
      _, err, status = Open3.capture3({ "PHOMEMO_PICORUBY" => VM }, BIN, "--png", png, STRIPES)
      assert_equal 2, status.exitstatus
      assert_match(/--png needs --dry-run/, err)
      refute File.exist?(png)
    end
  end
end
