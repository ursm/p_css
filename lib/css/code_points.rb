module CSS
  # Character class predicates from CSS Syntax §4.2 Definitions, plus the
  # U+FFFD replacement character used both during tokenization and
  # serialization. Implemented with char comparisons rather than regex to
  # avoid pattern-match overhead in the tokenizer's inner loop.
  module CodePoints
    REPLACEMENT = "�".freeze

    module_function

    def digit?(c)
      !c.nil? && c >= '0' && c <= '9'
    end

    def hex_digit?(c)
      return false if c.nil?

      (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')
    end

    def ident_start_code_point?(c)
      return false if c.nil?
      return true  if c == '_' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')

      c.ord >= 0x80
    end

    def ident_code_point?(c)
      return false if c.nil?
      return true  if c == '_' || c == '-' || (c >= '0' && c <= '9')
      return true  if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')

      c.ord >= 0x80
    end
  end
end
