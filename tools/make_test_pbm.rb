module MakeTestPbm
  WIDTH = 384
  ROW_BYTES = 48
  PATTERNS = %w[topline ruler density chunk grid label]

  GLYPHS = {
    " " => %w[00000 00000 00000 00000 00000 00000 00000],
    "0" => %w[01110 10001 10011 10101 11001 10001 01110],
    "1" => %w[00100 01100 00100 00100 00100 00100 01110],
    "2" => %w[01110 10001 00001 00010 00100 01000 11111],
    "3" => %w[11110 00001 00001 01110 00001 00001 11110],
    "4" => %w[00010 00110 01010 10010 11111 00010 00010],
    "5" => %w[11111 10000 11110 00001 00001 10001 01110],
    "6" => %w[00110 01000 10000 11110 10001 10001 01110],
    "7" => %w[11111 00001 00010 00100 01000 01000 01000],
    "8" => %w[01110 10001 10001 01110 10001 10001 01110],
    "9" => %w[01110 10001 10001 01111 00001 00010 01100],
    "A" => %w[01110 10001 10001 11111 10001 10001 10001],
    "B" => %w[11110 10001 10001 11110 10001 10001 11110],
    "C" => %w[01110 10001 10000 10000 10000 10001 01110],
    "D" => %w[11100 10010 10001 10001 10001 10010 11100],
    "E" => %w[11111 10000 10000 11110 10000 10000 11111],
    "F" => %w[11111 10000 10000 11110 10000 10000 10000],
    "G" => %w[01110 10001 10000 10111 10001 10001 01111],
    "H" => %w[10001 10001 10001 11111 10001 10001 10001],
    "I" => %w[01110 00100 00100 00100 00100 00100 01110],
    "J" => %w[00111 00010 00010 00010 00010 10010 01100],
    "K" => %w[10001 10010 10100 11000 10100 10010 10001],
    "L" => %w[10000 10000 10000 10000 10000 10000 11111],
    "M" => %w[10001 11011 10101 10101 10001 10001 10001],
    "N" => %w[10001 10001 11001 10101 10011 10001 10001],
    "O" => %w[01110 10001 10001 10001 10001 10001 01110],
    "P" => %w[11110 10001 10001 11110 10000 10000 10000],
    "Q" => %w[01110 10001 10001 10001 10101 10010 01101],
    "R" => %w[11110 10001 10001 11110 10100 10010 10001],
    "S" => %w[01111 10000 10000 01110 00001 00001 11110],
    "T" => %w[11111 00100 00100 00100 00100 00100 00100],
    "U" => %w[10001 10001 10001 10001 10001 10001 01110],
    "V" => %w[10001 10001 10001 10001 10001 01010 00100],
    "W" => %w[10001 10001 10001 10101 10101 10101 01010],
    "X" => %w[10001 10001 01010 00100 01010 10001 10001],
    "Y" => %w[10001 10001 01010 00100 00100 00100 00100],
    "Z" => %w[11111 00001 00010 00100 01000 10000 11111],
    "=" => %w[00000 00000 11111 00000 11111 00000 00000],
    "-" => %w[00000 00000 00000 11111 00000 00000 00000]
  }

  GLYPH_SCALE = 3
  GLYPH_PITCH = 6 * GLYPH_SCALE
  LABEL_MARGIN = 8
  LABEL_PAD = 2
  LABEL_MAX_CHARS = (WIDTH - LABEL_MARGIN * 2) / GLYPH_PITCH

  BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5]
  ]

  WHITE = ("\x00".b * ROW_BYTES).freeze
  BLACK = ("\xff".b * ROW_BYTES).freeze

  def self.render(pattern, text = nil, label: nil)
    raise ArgumentError, "unknown pattern: #{pattern}" unless PATTERNS.include?(pattern)
    rows = send("rows_#{pattern}", text)
    rows = rows_label(label) + rows if label
    "P4\n#{WIDTH} #{rows.size}\n".b + rows.join
  end

  def self.tick(bytes)
    ("\xff".b * bytes) + ("\x00".b * (ROW_BYTES - bytes))
  end

  def self.rows_topline(_text)
    Array.new(96) do |r|
      if r < 3 then BLACK
      elsif r % 80 == 0 then tick(24)
      elsif r % 8 == 0 then tick(8)
      else WHITE
      end
    end
  end

  def self.rows_ruler(_text)
    Array.new(160) do |r|
      if r >= 156 then BLACK
      elsif r % 80 == 0 then tick(24)
      elsif r % 8 == 0 then tick(8)
      else WHITE
      end
    end
  end

  def self.rows_grid(_text)
    Array.new(133) do |r|
      next BLACK if r < 3
      next WHITE if r >= 85
      y = r - 3
      next BLACK if y % 40 == 0 || y % 80 == 1
      bits = Array.new(WIDTH, 0)
      (0...WIDTH).step(2) { |x| bits[x] = 1 } if y % 8 == 0
      (0...WIDTH).step(8) { |x| bits[x] = 1 if y.even? }
      (0...WIDTH).step(40) { |x| bits[x] = bits[x + 1] = 1 }
      (80...WIDTH).step(80) { |x| (x...x + 4).each { |i| bits[i] = 1 } }
      (190..193).each { |x| bits[x] = 1 }
      if y.between?(2, 9)
        k = y - 2
        (184 + k..199 - k).each { |x| bits[x] = 1 }
      elsif y.between?(72, 79)
        j = y - 72
        (191 - j..192 + j).each { |x| bits[x] = 1 }
      end
      [0, 1, 382, 383].each { |x| bits[x] = 1 }
      [bits.join].pack("B*")
    end
  end

  def self.rows_density(_text)
    (1..16).flat_map do |level|
      Array.new(8) do |r|
        bits = Array.new(WIDTH) { |x| BAYER[r % 4][x % 4] < level ? 1 : 0 }
        [bits.join].pack("B*")
      end
    end
  end

  def self.rows_chunk(_text)
    Array.new(120) { |r| r % 8 == 0 ? BLACK : "\x80".b * ROW_BYTES }
  end

  def self.rows_label(text)
    raise ArgumentError, "label text is required" if text.nil? || text.empty?
    chars = text.upcase.chars
    raise ArgumentError, "label text is longer than #{LABEL_MAX_CHARS} characters" if chars.size > LABEL_MAX_CHARS
    chars.each { |c| raise ArgumentError, "unsupported label character: #{c}" unless GLYPHS.key?(c) }

    bits = Array.new(7 * GLYPH_SCALE) { Array.new(WIDTH, 0) }
    chars.each_with_index do |c, i|
      GLYPHS[c].each_with_index do |glyph_row, gy|
        glyph_row.each_char.with_index do |dot, gx|
          next if dot == "0"
          GLYPH_SCALE.times do |dy|
            GLYPH_SCALE.times do |dx|
              bits[gy * GLYPH_SCALE + dy][LABEL_MARGIN + i * GLYPH_PITCH + gx * GLYPH_SCALE + dx] = 1
            end
          end
        end
      end
    end
    text_rows = bits.map { |row| [row.join].pack("B*") }
    Array.new(LABEL_PAD, WHITE) + text_rows + Array.new(LABEL_PAD, WHITE) + [BLACK]
  end
end

if $PROGRAM_NAME == __FILE__
  usage = "usage: ruby #{$PROGRAM_NAME} <#{MakeTestPbm::PATTERNS.join('|')}> <out.pbm> [TEXT... | --label TEXT...]"
  usage_error = lambda do |message = nil|
    warn message if message
    warn usage
    exit 2
  end
  pattern, out, *rest = ARGV
  usage_error.call if pattern.nil? || out.nil?
  usage_error.call("unknown pattern: #{pattern}") unless MakeTestPbm::PATTERNS.include?(pattern)

  begin
    data =
      if pattern == "label"
        MakeTestPbm.render("label", rest.join(" "))
      elsif rest.first == "--label"
        MakeTestPbm.render(pattern, label: rest.drop(1).join(" "))
      elsif rest.empty?
        MakeTestPbm.render(pattern)
      else
        usage_error.call
      end
  rescue ArgumentError => e
    usage_error.call(e.message)
  end
  File.binwrite(out, data)
end
