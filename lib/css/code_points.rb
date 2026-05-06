module CSS
  # Character class predicates from CSS Syntax §4.2 Definitions, plus the
  # U+FFFD replacement character used both during tokenization and
  # serialization.
  #
  # ASCII bytes are looked up in a precomputed boolean table (one Array
  # access + one branch); non-ASCII code points (>= 0x80) are always
  # ident-cp / ident-start per spec, so the helpers fall back to a single
  # `c.ord >= 0x80` check. Avoids the chain of `String#<=>` calls a
  # range-style predicate would dispatch.
  module CodePoints
    REPLACEMENT = "�".freeze

    DIGIT_TABLE = Array.new(128, false).tap {|a|
      (0x30..0x39).each { a[it] = true }
    }.freeze

    HEX_DIGIT_TABLE = Array.new(128, false).tap {|a|
      (0x30..0x39).each { a[it] = true }
      (0x41..0x46).each { a[it] = true }
      (0x61..0x66).each { a[it] = true }
    }.freeze

    IDENT_START_TABLE = Array.new(128, false).tap {|a|
      (0x41..0x5A).each { a[it] = true }
      (0x61..0x7A).each { a[it] = true }
      a[0x5F] = true # _
    }.freeze

    IDENT_CP_TABLE = Array.new(128, false).tap {|a|
      (0x30..0x39).each { a[it] = true }
      (0x41..0x5A).each { a[it] = true }
      (0x61..0x7A).each { a[it] = true }
      a[0x5F] = true # _
      a[0x2D] = true # -
    }.freeze

    module_function

    def digit?(c)
      return false if c.nil?

      o = c.ord
      o < 128 && DIGIT_TABLE[o]
    end

    def hex_digit?(c)
      return false if c.nil?

      o = c.ord
      o < 128 && HEX_DIGIT_TABLE[o]
    end

    def ident_start_code_point?(c)
      return false if c.nil?

      o = c.ord
      o >= 128 || IDENT_START_TABLE[o]
    end

    def ident_code_point?(c)
      return false if c.nil?

      o = c.ord
      o >= 128 || IDENT_CP_TABLE[o]
    end
  end
end
