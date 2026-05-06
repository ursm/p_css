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

    def self.build_table(*ranges_or_ints)
      Array.new(128, false).tap {|a|
        ranges_or_ints.each {|r|
          if r.is_a?(Range) then r.each { a[it] = true }
          else                   a[r] = true
          end
        }
      }.freeze
    end

    DIGIT_TABLE       = build_table(0x30..0x39)
    HEX_DIGIT_TABLE   = build_table(0x30..0x39, 0x41..0x46, 0x61..0x66)
    IDENT_START_TABLE = build_table(0x41..0x5A, 0x61..0x7A, 0x5F)
    IDENT_CP_TABLE    = build_table(0x30..0x39, 0x41..0x5A, 0x61..0x7A, 0x5F, 0x2D)

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
