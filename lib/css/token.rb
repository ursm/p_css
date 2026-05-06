module CSS
  # Source location of a token within the preprocessed input. `offset` and
  # `end_offset` are 0-based character indices; `line` and `column` are
  # 1-based.
  Position = Data.define(:line, :column, :offset, :end_offset) do
    def to_s
      "#{line}:#{column}"
    end
  end

  class Token
    TYPES = %i[
      ident function at_keyword hash string bad_string url bad_url
      delim number percentage dimension whitespace cdo cdc comment
      colon semicolon comma
      lbracket rbracket lparen rparen lbrace rbrace
      eof
    ].freeze

    attr_reader :type, :value, :flag, :unit

    def initialize(type, value = nil, flag: nil, unit: nil, position: nil)
      raise ArgumentError, "unknown token type: #{type.inspect}" unless TYPES.include?(type)

      @type          = type
      @value         = value
      @flag          = flag
      @unit          = unit
      @position      = position
      @start_offset  = nil
      @end_offset    = nil
      @newlines      = nil
    end

    # Position is intentionally excluded from equality so that hand-built
    # tokens compare equal to parsed tokens.
    def ==(other)
      other.is_a?(Token) &&
        other.type  == type &&
        other.value == value &&
        other.flag  == flag &&
        other.unit  == unit
    end
    alias eql? ==

    def hash
      [type, value, flag, unit].hash
    end

    def whitespace?
      type == :whitespace
    end

    def comment?
      type == :comment
    end

    # True for tokens that don't carry semantic content — used by the parser
    # to skip insignificant tokens between meaningful ones.
    def trivia?
      type == :whitespace || type == :comment
    end

    # Most tokens never have their `position` read after parsing, so we
    # build the `Position` Data only on demand. The tokenizer plants the
    # bare offsets + a shared reference to its newline index.
    def assign_source!(start_offset, end_offset, newlines)
      @start_offset = start_offset
      @end_offset   = end_offset
      @newlines     = newlines
      self
    end

    def position
      return @position if @position
      return nil if @start_offset.nil?

      @position = compute_position
    end

    # Mutating: assigns the token's source position and returns self.
    # Useful for callers building tokens by hand who already have a
    # Position; the tokenizer goes through `assign_source!` instead.
    def assign_position!(pos)
      @position = pos
      self
    end

    def inspect
      parts = ["type=#{type.inspect}"]
      parts << "value=#{value.inspect}" unless value.nil?
      parts << "flag=#{flag.inspect}"   unless flag.nil?
      parts << "unit=#{unit.inspect}"   unless unit.nil?
      parts << "@#{position}"           unless position.nil?

      "#<CSS::Token #{parts.join(' ')}>"
    end

    private

    def compute_position
      idx     = @newlines.bsearch_index { it >= @start_offset } || @newlines.size
      prev_nl = idx.zero? ? -1 : @newlines[idx - 1]

      Position.new(
        line:       idx + 1,
        column:     @start_offset - prev_nl,
        offset:     @start_offset,
        end_offset: @end_offset
      )
    end
  end
end
