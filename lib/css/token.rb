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
      delim number percentage dimension whitespace cdo cdc
      colon semicolon comma
      lbracket rbracket lparen rparen lbrace rbrace
      eof
    ].freeze

    attr_reader :type, :value, :flag, :unit, :position

    def initialize(type, value = nil, flag: nil, unit: nil, position: nil)
      raise ArgumentError, "unknown token type: #{type.inspect}" unless TYPES.include?(type)

      @type     = type
      @value    = value
      @flag     = flag
      @unit     = unit
      @position = position
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

    def with_position(pos)
      Token.new(type, value, flag:, unit:, position: pos)
    end

    def inspect
      parts = ["type=#{type.inspect}"]
      parts << "value=#{value.inspect}" unless value.nil?
      parts << "flag=#{flag.inspect}"   unless flag.nil?
      parts << "unit=#{unit.inspect}"   unless unit.nil?
      parts << "@#{position}"           unless position.nil?

      "#<CSS::Token #{parts.join(' ')}>"
    end
  end
end
