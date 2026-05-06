module CSS
  # Parser based on CSS Syntax Module Level 4 §5, with the nesting extensions
  # described in CSS Nesting Module Level 1 / Syntax 4.
  # https://drafts.csswg.org/css-syntax/
  class Parser
    include Nodes

    EOF_TOKEN = Token.new(:eof).freeze

    class << self
      def parse_stylesheet(input)            = build(input).parse_stylesheet
      def parse_rule(input)                  = build(input).parse_rule
      def parse_declaration(input)           = build(input).parse_declaration
      def parse_block_contents(input)        = build(input).parse_block_contents
      def parse_component_value(input)       = build(input).parse_component_value
      def parse_component_values(input)      = build(input).parse_component_values
      def parse_comma_separated_values(input) = build(input).parse_comma_separated_values

      private

      def build(input)
        tokens = input.is_a?(String) ? Tokenizer.new(input).tokenize : input.to_a
        new(tokens)
      end
    end

    def initialize(tokens)
      @tokens = tokens
      @pos    = 0
    end

    # §5.3.3 Parse a stylesheet.
    def parse_stylesheet
      Stylesheet.new(rules: consume_rule_list(top_level: true))
    end

    # §5.3.4 Parse a rule. Returns a single AtRule or QualifiedRule.
    # Raises ParseError when the input is empty or contains anything beyond
    # a single rule.
    def parse_rule
      skip_whitespace

      parse_error!('expected a rule, got end of input') if peek.type == :eof

      rule = if peek.type == :at_keyword
               consume_at_rule(nested: false)
             else
               consume_qualified_rule(nested: false)
             end

      parse_error!('invalid rule') if rule.nil?

      skip_whitespace

      parse_error!("unexpected token after rule: #{peek.type}") unless peek.type == :eof

      rule
    end

    # §5.3.5 Parse a declaration. Returns a Declaration. Raises ParseError on
    # invalid input. Trailing tokens after the declaration are ignored, per
    # the spec algorithm.
    def parse_declaration
      skip_whitespace

      parse_error!('expected a declaration') unless peek.type == :ident

      decl = try_consume_declaration

      parse_error!('invalid declaration') unless decl

      decl
    end

    # §5.4.4 Parse a block's contents. Returns a Block whose items are a mix
    # of Declarations and nested rules. Used for parsing the content of a
    # `style="..."` attribute, or for `@page` etc.
    def parse_block_contents
      Block.new(items: collect_block_items(stop_at_close_brace: false))
    end

    # §5.3.7 Parse a component value. Returns a Token, Function, or
    # SimpleBlock. Raises ParseError on empty input or on extra tokens.
    def parse_component_value
      skip_whitespace

      parse_error!('expected a component value') if peek.type == :eof

      cv = consume_component_value

      skip_whitespace

      parse_error!("unexpected token after component value: #{peek.type}") unless peek.type == :eof

      cv
    end

    # §5.3.8 Parse a list of component values. Returns an Array.
    def parse_component_values
      values = []
      values << consume_component_value until peek.type == :eof
      values
    end

    # §5.3.9 Parse a comma-separated list of component values. Returns an
    # Array of Arrays. An empty input produces `[[]]`; trailing comma
    # produces an empty trailing group.
    def parse_comma_separated_values
      groups  = []
      current = []

      loop do
        case peek.type
        when :eof
          groups << current
          return groups
        when :comma
          consume
          groups << current
          current = []
        else
          current << consume_component_value
        end
      end
    end

    private

    def parse_error!(message)
      raise ParseError.new(message, position: peek.position)
    end

    def peek(offset = 0)
      @tokens[@pos + offset] || EOF_TOKEN
    end

    def consume
      tok = @tokens[@pos] || EOF_TOKEN
      @pos += 1
      tok
    end

    def reconsume
      @pos -= 1
    end

    def skip_whitespace
      consume while peek.type == :whitespace
    end

    # Consume a list of rules from the current position. At the top level,
    # CDO and CDC tokens are silently dropped. Inside a block, an unmatched
    # `}` ends the list.
    def consume_rule_list(top_level:)
      rules = []

      loop do
        t = peek

        case t.type
        when :eof
          return rules
        when :whitespace, :semicolon
          consume
        when :cdo, :cdc
          if top_level
            consume
          else
            rule = consume_qualified_rule(nested: !top_level)
            rules << rule if rule
          end
        when :at_keyword
          rule = consume_at_rule(nested: !top_level)
          rules << rule if rule
        else
          rule = consume_qualified_rule(nested: !top_level)
          rules << rule if rule
        end
      end
    end

    # Consume an at-rule. The current position is at the at-keyword token.
    def consume_at_rule(nested:)
      name    = consume.value
      prelude = []
      block   = nil

      loop do
        t = peek

        case t.type
        when :semicolon, :eof
          consume if t.type == :semicolon
          break
        when :rbrace
          break if nested

          prelude << consume
        when :lbrace
          consume
          block = consume_braced_block
          break
        else
          prelude << consume_component_value
        end
      end

      trim_leading_whitespace!(prelude)
      trim_trailing_whitespace!(prelude)
      AtRule.new(name:, prelude:, block:)
    end

    # Consume a qualified rule. May return nil on parse error.
    def consume_qualified_rule(nested:)
      saved   = @pos
      prelude = []

      loop do
        t = peek

        case t.type
        when :eof
          @pos = saved
          return nil
        when :rbrace
          if nested
            @pos = saved
            return nil
          end

          prelude << consume
        when :semicolon
          if nested
            consume
            return nil
          end

          prelude << consume
        when :lbrace
          consume
          block = consume_braced_block
          trim_leading_whitespace!(prelude)
          trim_trailing_whitespace!(prelude)
          return QualifiedRule.new(prelude:, block:)
        else
          prelude << consume_component_value
        end
      end
    end

    # Consume the contents of a `{}` block (declarations + nested rules).
    # The opening `{` has already been consumed; this consumes through the
    # matching `}`.
    def consume_braced_block
      Block.new(items: collect_block_items(stop_at_close_brace: true))
    end

    # Shared loop body for both `{}`-terminated blocks (inside a rule) and
    # EOF-terminated block contents (style attribute, `@page`, etc.).
    def collect_block_items(stop_at_close_brace:)
      items = []

      loop do
        t = peek

        case t.type
        when :eof
          return items
        when :rbrace
          consume
          return items if stop_at_close_brace

          # Stray `}` outside any block: parse error per spec; skip and
          # continue.
        when :whitespace, :semicolon
          consume
        when :at_keyword
          rule = consume_at_rule(nested: true)
          items << rule if rule
        else
          decl = try_consume_declaration
          if decl
            items << decl
          else
            rule = consume_qualified_rule(nested: true)
            items << rule if rule
          end
        end
      end
    end

    # Try to consume a declaration. Returns the declaration on success, or nil
    # on failure (in which case the parser position is restored).
    #
    # In nested context a token sequence like `a:hover { ... }` looks like the
    # start of a declaration (`<ident> : ...`). We detect such cases by
    # noticing a `{}` simple block in the value and treating the input as a
    # nested qualified rule instead.
    def try_consume_declaration
      saved = @pos

      return nil unless peek.type == :ident

      name = consume.value

      skip_whitespace

      unless peek.type == :colon
        @pos = saved
        return nil
      end

      consume

      value = []

      loop do
        t = peek

        case t.type
        when :semicolon
          consume
          break
        when :eof, :rbrace
          break
        else
          value << consume_component_value
        end
      end

      if value.any? { it.is_a?(SimpleBlock) && it.open == '{' }
        @pos = saved
        return nil
      end

      important = extract_important!(value)

      trim_leading_whitespace!(value)
      trim_trailing_whitespace!(value)

      Declaration.new(name:, value:, important:)
    end

    def consume_component_value
      t = peek

      case t.type
      when :lbrace, :lbracket, :lparen
        consume_simple_block
      when :function
        consume_function
      else
        consume
      end
    end

    def consume_simple_block
      open_tok  = consume
      open_char = simple_block_open_char(open_tok.type)
      end_type  = simple_block_end_type(open_tok.type)
      values    = []

      loop do
        t = peek

        case t.type
        when :eof
          break
        when end_type
          consume
          break
        else
          values << consume_component_value
        end
      end

      SimpleBlock.new(open: open_char, value: values)
    end

    def consume_function
      name   = consume.value
      values = []

      loop do
        t = peek

        case t.type
        when :eof
          break
        when :rparen
          consume
          break
        else
          values << consume_component_value
        end
      end

      Function.new(name:, value: values)
    end

    def simple_block_open_char(type)
      case type
      when :lbrace   then '{'
      when :lbracket then '['
      when :lparen   then '('
      end
    end

    def simple_block_end_type(type)
      case type
      when :lbrace   then :rbrace
      when :lbracket then :rbracket
      when :lparen   then :rparen
      end
    end

    def trim_leading_whitespace!(value)
      value.shift while value.first.is_a?(Token) && value.first.type == :whitespace
    end

    def trim_trailing_whitespace!(value)
      value.pop while value.last.is_a?(Token) && value.last.type == :whitespace
    end

    # Strip a trailing `! important` from the value list and return whether it
    # was present.
    def extract_important!(value)
      i = value.length - 1
      i -= 1 while i >= 0 && whitespace_token?(value[i])

      return false unless i >= 1

      ident = value[i]

      return false unless ident.is_a?(Token) && ident.type == :ident && ident.value.casecmp('important').zero?

      j = i - 1
      j -= 1 while j >= 0 && whitespace_token?(value[j])

      bang = value[j]

      return false unless bang.is_a?(Token) && bang.type == :delim && bang.value == '!'

      value.slice!(j..)
      true
    end

    def whitespace_token?(item)
      item.is_a?(Token) && item.type == :whitespace
    end
  end
end
