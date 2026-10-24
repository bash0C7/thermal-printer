module PhomemoThermalPrinter
  class PbmReader
    WIDTH = 384
    ROW_BYTES = 48

    attr_reader :width, :height

    def initialize(io, max_rows: 255)
      @io = io
      @max_rows = max_rows
      @row = 0
      @header_bytes = 0
      magic = read_token
      raise FormatError, "not a P4 PBM" unless magic == "P4"
      @width = read_token.to_i
      @height = read_token.to_i
      raise FormatError, "width must be #{WIDTH}" unless @width == WIDTH
      raise FormatError, "height must be positive" unless @height > 0
    end

    def complete_in?(file_size)
      file_size >= @header_bytes + ROW_BYTES * @height
    end

    def next_block
      remaining = @height - @row
      return nil if remaining <= 0
      rows = remaining < @max_rows ? remaining : @max_rows
      bytes = read_exact(rows * ROW_BYTES)
      @row += rows
      [rows, bytes]
    end

    private

    def read_byte_string
      s = @io.read(1)
      raise FormatError, "truncated header" if s.nil? || s.bytesize == 0
      @header_bytes += 1
      s
    end

    def read_token
      s = read_byte_string
      b = s.getbyte(0)
      while b == 35 || b == 32 || (b >= 9 && b <= 13)
        if b == 35
          while b != 10
            b = read_byte_string.getbyte(0)
          end
        end
        s = read_byte_string
        b = s.getbyte(0)
      end
      token = ""
      while !(b == 32 || (b >= 9 && b <= 13))
        token << s
        s = read_byte_string
        b = s.getbyte(0)
      end
      token
    end

    def read_exact(n)
      buf = ""
      while buf.bytesize < n
        part = @io.read(n - buf.bytesize)
        raise FormatError, "truncated raster" if part.nil? || part.bytesize == 0
        buf << part
      end
      buf
    end
  end
end
