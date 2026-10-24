module PhomemoThermalPrinter
  class Chunker
    MIN_SIZE = 20
    MAX_SIZE = 182
    RASTER_HEADER_SIZE = 8

    def initialize(size)
      check_size(size, "size")
      @size = size
      @buffer = ""
      @headers = []
    end

    def limit(max_write)
      check_size_floor(max_write, "max_write")
      @size = max_write if max_write < @size
    end

    def push(segment)
      @headers << @buffer.bytesize if raster?(segment)
      @buffer << segment
      size = @size
      total = @buffer.bytesize
      out = []
      pos = 0
      while total - pos >= size
        cut = cut_length(pos, size)
        out << @buffer.byteslice(pos, cut)
        pos += cut
      end
      if pos > 0
        @buffer = @buffer.byteslice(pos, total - pos)
        rebase(pos)
      end
      out
    end

    def flush
      return nil if @buffer.bytesize == 0
      rest = @buffer
      @buffer = ""
      @headers = []
      rest
    end

    private

    def raster?(segment)
      segment.bytesize >= RASTER_HEADER_SIZE && segment.getbyte(0) == 0x1d &&
        segment.getbyte(1) == 0x76 && segment.getbyte(2) == 0x30
    end

    def cut_length(pos, size)
      edge = pos + size
      headers = @headers
      i = 0
      while i < headers.size
        start = headers[i]
        return start - pos if start < edge && edge < start + RASTER_HEADER_SIZE
        i += 1
      end
      size
    end

    def rebase(pos)
      keep = []
      headers = @headers
      i = 0
      while i < headers.size
        keep << headers[i] - pos if headers[i] >= pos
        i += 1
      end
      @headers = keep
    end

    def check_size(n, name)
      unless n.is_a?(Integer) && MIN_SIZE <= n && n <= MAX_SIZE
        raise ArgumentError, "#{name} must be an Integer in #{MIN_SIZE}..#{MAX_SIZE}"
      end
    end

    def check_size_floor(n, name)
      unless n.is_a?(Integer) && MIN_SIZE <= n
        raise ArgumentError, "#{name} must be an Integer of at least #{MIN_SIZE}"
      end
    end
  end
end
