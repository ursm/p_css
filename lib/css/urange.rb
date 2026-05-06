module CSS
  # Parser for CSS <urange> tokens, e.g. `U+0-7F`, `U+26`, `U+10??`.
  # https://drafts.csswg.org/css-syntax/#urange-syntax
  #
  # Operates on the source string rather than a token stream because the
  # tokenizer destructively normalizes shapes like `U+0` (the `+` is
  # absorbed into a number-token whose sign is lost on serialization).
  # Sticking with the source preserves the exact form.
  module Urange
    URANGE_RE   = /\Au\+([0-9a-f?]{1,6})(?:-([0-9a-f]{1,6}))?\z/i.freeze
    WILDCARD_RE = /\A[0-9a-f]*\?+\z/i.freeze

    MAX_CODEPOINT = 0x10FFFF

    extend self

    def parse(input)
      s = input.to_s.strip
      m = URANGE_RE.match(s)

      raise ParseError, "invalid urange: #{input.inspect}" unless m

      start_str, end_str = m[1], m[2]

      first, last =
        if end_str
          raise ParseError, 'wildcards are not allowed in range form' if start_str.include?('?')

          [start_str.to_i(16), end_str.to_i(16)]
        elsif start_str.include?('?')
          raise ParseError, 'wildcards must be trailing' unless start_str.match?(WILDCARD_RE)

          [start_str.tr('?', '0').to_i(16), start_str.tr('?', 'f').to_i(16)]
        else
          n = start_str.to_i(16)
          [n, n]
        end

      raise ParseError, "codepoint out of range: U+#{format('%X', last)}" if last > MAX_CODEPOINT
      raise ParseError, "urange start must be <= end (U+#{format('%X', first)} > U+#{format('%X', last)})" if first > last

      Nodes::UnicodeRange.new(first:, last:)
    end
  end
end
