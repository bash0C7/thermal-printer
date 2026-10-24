module PhomemoThermalPrinter
  class PngWriter
    SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].pack("C*")
    PALETTE = [0xff, 0xff, 0xff, 0x00, 0x00, 0x00].pack("C*")
    FILTER_NONE = [0].pack("C*")
    ZLIB_HEADER = [0x78, 0x01].pack("C*")
    MAX_STORED = 65535
    ADLER_MOD = 65521
    ADLER_RUN = 5552

    def self.build_crc_table
      table = []
      n = 0
      while n < 256
        c = n
        k = 0
        while k < 8
          if c & 1 == 1
            c = 0xedb88320 ^ (c >> 1)
          else
            c = c >> 1
          end
          k += 1
        end
        table << c
        n += 1
      end
      table
    end

    CRC_TABLE = build_crc_table

    def self.crc32(bytes, crc = 0)
      table = CRC_TABLE
      c = crc ^ 0xffffffff
      n = bytes.bytesize
      i = 0
      while i < n
        c = table[(c ^ bytes.getbyte(i)) & 0xff] ^ (c >> 8)
        i += 1
      end
      c ^ 0xffffffff
    end

    def self.adler32(bytes)
      a = 1
      b = 0
      n = bytes.bytesize
      i = 0
      while i < n
        stop = i + ADLER_RUN
        stop = n if stop > n
        while i < stop
          a += bytes.getbyte(i)
          b += a
          i += 1
        end
        a %= ADLER_MOD
        b %= ADLER_MOD
      end
      (b << 16) | a
    end

    def self.encode(packed, width, height)
      row_bytes = (width + 7) / 8
      unless width > 0 && height > 0 && packed.bytesize == row_bytes * height
        raise ArgumentError, "packed must hold exactly #{row_bytes} bytes for each of #{height} rows"
      end
      out = ""
      out << SIGNATURE
      out << chunk("IHDR", be32(width) + be32(height) + [1, 3, 0, 0, 0].pack("C*"))
      out << chunk("PLTE", PALETTE)
      out << chunk("IDAT", zlib_stored(filtered_rows(packed, row_bytes, height)))
      out << chunk("IEND", "")
      out
    end

    def self.filtered_rows(packed, row_bytes, height)
      raw = ""
      r = 0
      while r < height
        raw << FILTER_NONE
        raw << packed.byteslice(r * row_bytes, row_bytes)
        r += 1
      end
      raw
    end

    def self.zlib_stored(raw)
      out = ""
      out << ZLIB_HEADER
      total = raw.bytesize
      pos = 0
      while pos < total
        len = total - pos
        len = MAX_STORED if len > MAX_STORED
        final = pos + len >= total ? 1 : 0
        nlen = len ^ 0xffff
        out << [final, len & 0xff, len >> 8, nlen & 0xff, nlen >> 8].pack("C*")
        out << raw.byteslice(pos, len)
        pos += len
      end
      out << be32(adler32(raw))
      out
    end

    def self.chunk(type, data)
      out = ""
      out << be32(data.bytesize)
      out << type
      out << data
      out << be32(crc32(data, crc32(type)))
      out
    end

    def self.be32(n)
      [(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff].pack("C*")
    end
  end
end
