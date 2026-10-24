class PngWriterTest < Picotest::Test
  HEX = "0123456789abcdef"

  EIGHT_BY_TWO = "89504e470d0a1a0a0000000d49484452000000080000000201030000005f5a0fae" \
                 "00000006504c5445ffffff00000055c2d37e0000000f494441547801010400fbff" \
                 "00aa00f002f2019bdc2793ef0000000049454e44ae426082"

  def hex_of(bytes)
    out = ""
    i = 0
    while i < bytes.bytesize
      b = bytes.getbyte(i)
      out << HEX[b >> 4] << HEX[b & 15]
      i += 1
    end
    out
  end

  def be32(bytes, pos)
    (bytes.getbyte(pos) << 24) | (bytes.getbyte(pos + 1) << 16) | (bytes.getbyte(pos + 2) << 8) | bytes.getbyte(pos + 3)
  end

  def chunks_of(png)
    list = []
    pos = 8
    while pos < png.bytesize
      len = be32(png, pos)
      list << [png.byteslice(pos + 4, 4), png.byteslice(pos + 8, len), be32(png, pos + 8 + len)]
      pos += 12 + len
    end
    list
  end

  def chunk_named(png, name)
    list = chunks_of(png)
    i = 0
    while i < list.size
      return list[i] if list[i][0] == name
      i += 1
    end
    nil
  end

  def stored_blocks(zlib)
    blocks = []
    pos = 2
    while pos < zlib.bytesize - 4
      len = zlib.getbyte(pos + 1) | (zlib.getbyte(pos + 2) << 8)
      nlen = zlib.getbyte(pos + 3) | (zlib.getbyte(pos + 4) << 8)
      blocks << [zlib.getbyte(pos), len, nlen, zlib.byteslice(pos + 5, len)]
      pos += 5 + len
    end
    blocks
  end

  def test_crc32_of_the_check_string
    assert_equal 0xcbf43926, PhomemoThermalPrinter::PngWriter.crc32("123456789")
    assert_equal 0, PhomemoThermalPrinter::PngWriter.crc32("")
    assert_equal 0xae426082, PhomemoThermalPrinter::PngWriter.crc32("IEND")
  end

  def test_adler32_of_the_check_string
    assert_equal 0x091e01de, PhomemoThermalPrinter::PngWriter.adler32("123456789")
    assert_equal 1, PhomemoThermalPrinter::PngWriter.adler32("")
  end

  def test_adler32_survives_a_run_longer_than_one_modulo_block
    data = "\xff" * 20000
    a = 1
    b = 0
    i = 0
    while i < data.bytesize
      a = (a + 255) % 65521
      b = (b + a) % 65521
      i += 1
    end
    assert_equal (b << 16) | a, PhomemoThermalPrinter::PngWriter.adler32(data)
  end

  def test_an_8x2_image_encodes_to_the_exact_bytes
    png = PhomemoThermalPrinter::PngWriter.encode("\xaa\xf0", 8, 2)
    assert_equal EIGHT_BY_TWO, hex_of(png)
  end

  def test_the_result_is_a_binary_string_that_starts_with_the_png_signature
    png = PhomemoThermalPrinter::PngWriter.encode("\x00" * 96, 384, 2)
    assert_equal "89504e470d0a1a0a", hex_of(png.byteslice(0, 8))
  end

  def test_ihdr_has_the_size_and_the_1bit_palette_format
    png = PhomemoThermalPrinter::PngWriter.encode("\x00" * (48 * 600), 384, 600)
    ihdr = chunk_named(png, "IHDR")[1]
    assert_equal 384, be32(ihdr, 0)
    assert_equal 600, be32(ihdr, 4)
    assert_equal "0103000000", hex_of(ihdr.byteslice(8, 5))
  end

  def test_the_palette_is_white_then_black
    png = PhomemoThermalPrinter::PngWriter.encode("\x00" * 48, 384, 1)
    assert_equal "ffffff000000", hex_of(chunk_named(png, "PLTE")[1])
  end

  def test_every_chunk_crc_covers_its_type_and_data
    png = PhomemoThermalPrinter::PngWriter.encode("\xa5" * (48 * 40), 384, 40)
    list = chunks_of(png)
    assert_equal ["IHDR", "PLTE", "IDAT", "IEND"], [list[0][0], list[1][0], list[2][0], list[3][0]]
    i = 0
    while i < list.size
      assert_equal PhomemoThermalPrinter::PngWriter.crc32(list[i][0] + list[i][1]), list[i][2]
      i += 1
    end
  end

  def test_each_row_starts_with_filter_byte_0
    png = PhomemoThermalPrinter::PngWriter.encode("\x11\x22\x33", 8, 3)
    raw = stored_blocks(chunk_named(png, "IDAT")[1])[0][3]
    assert_equal "001100220033", hex_of(raw)
  end

  def test_a_raw_size_of_exactly_65535_is_one_final_block
    packed = "\x5a" * (256 * 255)
    png = PhomemoThermalPrinter::PngWriter.encode(packed, 2048, 255)
    blocks = stored_blocks(chunk_named(png, "IDAT")[1])
    assert_equal 1, blocks.size
    assert_equal 1, blocks[0][0]
    assert_equal 65535, blocks[0][1]
    assert_equal 0, blocks[0][2]
  end

  def test_a_raw_size_over_65535_splits_into_blocks_with_only_the_last_final
    packed = "\x3c" * 70000
    png = PhomemoThermalPrinter::PngWriter.encode(packed, 8, 70000)
    zlib = chunk_named(png, "IDAT")[1]
    blocks = stored_blocks(zlib)
    assert_equal [0, 0, 1], [blocks[0][0], blocks[1][0], blocks[2][0]]
    assert_equal [65535, 65535, 8930], [blocks[0][1], blocks[1][1], blocks[2][1]]
    assert_equal 0xffff, blocks[0][1] ^ blocks[0][2]
    assert_equal 0xffff, blocks[2][1] ^ blocks[2][2]
    raw = blocks[0][3] + blocks[1][3] + blocks[2][3]
    assert_equal 140000, raw.bytesize
    assert_equal PhomemoThermalPrinter::PngWriter.adler32(raw), be32(zlib, zlib.bytesize - 4)
    assert_equal "003c", hex_of(raw.byteslice(0, 2))
    assert_equal "003c", hex_of(raw.byteslice(139998, 2))
  end

  def test_a_size_that_does_not_match_the_pixel_data_is_refused
    assert_raise(ArgumentError) { PhomemoThermalPrinter::PngWriter.encode("\x00" * 47, 384, 1) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::PngWriter.encode("", 384, 0) }
  end
end
