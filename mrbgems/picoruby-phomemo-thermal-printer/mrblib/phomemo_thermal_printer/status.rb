module PhomemoThermalPrinter
  class StatusDecoder
    HEX_DIGITS = "0123456789abcdef"
    REPLY_LENGTHS = {
      0x03 => 2, 0x04 => 2, 0x05 => 2, 0x06 => 2, 0x07 => 4, 0x08 => 16,
      0x09 => 2, 0x0b => 2, 0x0e => 2, 0x0f => 2, 0x16 => 2, 0x17 => 2,
      0x1d => 2, 0x20 => 2, 0x35 => 2, 0x3b => 6
    }
    LOW_BATTERY_PERCENTS = [10, 5, 3, 0]

    def initialize
      @buf = []
    end

    def feed(bytes)
      buf = @buf
      n = bytes.bytesize
      i = 0
      while i < n
        buf << bytes.getbyte(i)
        i += 1
      end
      events = []
      size = buf.size
      pos = 0
      while pos < size
        head = buf[pos]
        left = size - pos
        if head == 0x01
          break if left < 2
          if buf[pos + 1] == 0x01
            events << [:ack]
            pos += 2
          else
            events << [:unknown, hex(buf, pos, left)]
            pos = size
          end
        elsif head == 0x02
          break if left < 3
          events << [:max_write, buf[pos + 1] + buf[pos + 2] * 256]
          pos += 3
        elsif head == 0x1a
          break if left < 2
          len = REPLY_LENGTHS[buf[pos + 1]]
          if len.nil?
            events << [:unknown, hex(buf, pos, left)]
            pos = size
          else
            break if left < 1 + len
            events << decode_reply(buf, pos + 1, len)
            pos += 1 + len
          end
        else
          events << [:unknown, hex(buf, pos, left)]
          pos = size
        end
      end
      @buf = pos >= size ? [] : buf[pos, size - pos]
      events
    end

    private

    def decode_reply(buf, start, len)
      type = buf[start]
      value = buf[start + 1]
      event = nil
      if type == 0x03
        event = [:temperature, :normal] if value == 0xa8
        event = [:temperature, :overheat] if value == 0xa9
      elsif type == 0x04
        if value <= 100
          event = [:battery, value]
        elsif value >= 0xa1 && value <= 0xa4
          event = [:battery, LOW_BATTERY_PERCENTS[value - 0xa1]]
        end
      elsif type == 0x05
        event = [:cover, :closed] if value == 0x98
        event = [:cover, :open] if value == 0x99
      elsif type == 0x06
        event = [:paper, :ok] if value == 0x89
        event = [:paper, :out] if value == 0x88
      elsif type == 0x07
        event = [:firmware, "#{value}.#{buf[start + 2]}.#{buf[start + 3]}"]
      elsif type == 0x08
        event = [:serial, buf[start + 1, len - 1].pack("C*")]
      elsif type == 0x09
        event = [:auto_off, value]
      elsif type == 0x0b
        event = [:canceled] if value == 0xb8
      elsif type == 0x0f
        event = value == 0x0c ? [:print_complete] : [:print_failed, value]
      end
      event || [:unknown, hex(buf, start - 1, len + 1)]
    end

    def hex(buf, from, count)
      out = ""
      i = from
      last = from + count
      while i < last
        byte = buf[i]
        out << HEX_DIGITS[byte >> 4] << HEX_DIGITS[byte & 0x0f]
        i += 1
      end
      out
    end
  end
end
