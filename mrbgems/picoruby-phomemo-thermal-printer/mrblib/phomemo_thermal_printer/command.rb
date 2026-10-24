module PhomemoThermalPrinter
  module Command
    QUERY_OPS = [0x07, 0x08, 0x09, 0x0e, 0x11, 0x12, 0x13]
    ROW_BYTES = 48

    def self.initialize_printer
      [0x1b, 0x40].pack("C*")
    end

    def self.align(n)
      check_range(n, 0, 2, "align")
      [0x1b, 0x61, n].pack("C*")
    end

    def self.density(n)
      check_range(n, 1, 5, "density")
      [0x1f, 0x11, 0x02, n].pack("C*")
    end

    def self.raster_header(rows)
      check_range(rows, 1, 255, "rows")
      [0x1d, 0x76, 0x30, 0x00, 0x30, 0x00, rows, 0x00].pack("C*")
    end

    def self.feed(n)
      check_range(n, 0, 255, "feed")
      [0x1b, 0x64, n].pack("C*")
    end

    def self.query(op)
      unless op.is_a?(Integer) && QUERY_OPS.include?(op)
        raise ArgumentError, "status query op is not in the allowlist"
      end
      [0x1f, 0x11, op].pack("C*")
    end

    def self.allowed?(segment)
      return false unless segment.is_a?(String)
      size = segment.bytesize
      return false if size == 0
      i = 0
      while i < size
        len = command_length(segment, i, size)
        return false if len == 0
        i += len
      end
      true
    end

    def self.check_range(n, min, max, name)
      unless n.is_a?(Integer) && min <= n && n <= max
        raise ArgumentError, "#{name} must be an Integer in #{min}..#{max}"
      end
    end

    def self.command_length(seg, i, size)
      b0 = seg.getbyte(i)
      rest = size - i
      if b0 == 0x1b
        return 0 if rest < 2
        b1 = seg.getbyte(i + 1)
        return 2 if b1 == 0x40
        return 0 if rest < 3
        n = seg.getbyte(i + 2)
        return 3 if b1 == 0x64
        return 3 if b1 == 0x61 && n <= 2
      elsif b0 == 0x1f
        return 0 if rest < 3 || seg.getbyte(i + 1) != 0x11
        op = seg.getbyte(i + 2)
        return 3 if QUERY_OPS.include?(op)
        if op == 0x02
          return 0 if rest < 4
          n = seg.getbyte(i + 3)
          return 4 if 1 <= n && n <= 5
        end
      elsif b0 == 0x1d
        return 0 if rest < 8
        return 0 unless seg.getbyte(i + 1) == 0x76 && seg.getbyte(i + 2) == 0x30
        return 0 unless seg.getbyte(i + 3) == 0x00 && seg.getbyte(i + 4) == 0x30
        return 0 unless seg.getbyte(i + 5) == 0x00 && seg.getbyte(i + 7) == 0x00
        rows = seg.getbyte(i + 6)
        return 0 if rows < 1
        total = 8 + ROW_BYTES * rows
        return total if rest >= total
      end
      0
    end
  end
end
