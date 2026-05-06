module CSS
  # Shared cursor used by the three parsers (`Selectors::Parser`,
  # `Selectors::AnBParser::Impl`, `MediaQueries::Parser`). Each one walks
  # an array of items with the same primitives — tokens for the selector
  # parsers, mixed Token / SimpleBlock / Function items for the media-
  # query parser. Predicates against the item's `.type` go through
  # `peek_token`, which collapses non-Token items to EOF safely.
  module TokenCursor
    EOF_TOKEN = Token.new(:eof).freeze

    def init_cursor(items)
      @items = items
      @pos   = 0
    end

    def peek(offset = 0)
      @items[@pos + offset] || EOF_TOKEN
    end

    # Returns peek unwrapped to a Token; non-Token items collapse to
    # EOF. Lets media-query code do `.type == :colon` against streams
    # that may also hold SimpleBlock / Function items.
    def peek_token
      item = peek
      item.is_a?(Token) ? item : EOF_TOKEN
    end

    def consume
      item = @items[@pos] || EOF_TOKEN
      @pos += 1
      item
    end

    def skip_whitespace
      while (item = peek).is_a?(Token) && item.type == :whitespace
        @pos += 1
      end
    end

    def eof?
      @pos >= @items.length
    end

    def parse_error!(message)
      pos = peek.respond_to?(:position) ? peek.position : nil
      raise ParseError.new(message, position: pos)
    end
  end
end
