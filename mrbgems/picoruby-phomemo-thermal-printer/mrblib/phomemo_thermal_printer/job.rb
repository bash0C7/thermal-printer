module PhomemoThermalPrinter
  class Job
    ROW_BYTES = 48

    attr_reader :rows, :blocks, :bytes

    def initialize(source, density:, feed: 3)
      @source = source
      @preamble = Command.initialize_printer + Command.align(0) + Command.density(density)
      @postamble = Command.feed(feed)
      @state = 0
      @rows = 0
      @blocks = 0
      @bytes = 0
    end

    def next_segment
      segment = nil
      if @state == 0
        segment = @preamble
        @state = 1
      elsif @state == 1
        segment = block_segment
        if segment.nil?
          segment = @postamble
          @state = 3
        end
      end
      @bytes += segment.bytesize if segment
      segment
    end

    private

    def block_segment
      block = @source.next_block
      return nil if block.nil?
      rows = block[0]
      body = block[1]
      header = Command.raster_header(rows)
      raise FormatError, "block bytes do not match its row count" unless body.bytesize == rows * ROW_BYTES
      @rows += rows
      @blocks += 1
      header + body
    end
  end
end
