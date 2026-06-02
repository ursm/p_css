module CSS
  # Parser based on CSS Syntax Module Level 4 §5, with the nesting extensions
  # described in CSS Nesting Module Level 1 / Syntax 4.
  # https://drafts.csswg.org/css-syntax/
  class Parser
    include Nodes

    # Shared sentinel returned past the end of the token stream. It has no
    # position, which is why ParseError messages at EOF show no `line:col:`
    # prefix.
    EOF_TOKEN = Token.new(:eof).freeze

    class << self
      def parse_stylesheet(input, **opts)             = build(input, **opts).parse_stylesheet
      def parse_rule(input, **opts)                   = build(input, **opts).parse_rule
      def parse_declaration(input, **opts)            = build(input, **opts).parse_declaration
      def parse_block_contents(input, **opts)         = build(input, **opts).parse_block_contents
      def parse_component_value(input, **opts)        = build(input, **opts).parse_component_value
      def parse_component_values(input, **opts)       = build(input, **opts).parse_component_values
      def parse_comma_separated_values(input, **opts) = build(input, **opts).parse_comma_separated_values

      private

      def build(input, **opts)
        tokens = input.is_a?(String) ? Tokenizer.new(input, **opts).tokenize : input.to_a
        new(tokens)
      end
    end

    def initialize(tokens)
      @tokens = tokens
      @pos    = 0
    end

    # §5.3.3.
    def parse_stylesheet
      Stylesheet.new(rules: consume_rule_list(top_level: true))
    end

    # §5.3.4.
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

    # §5.3.5. Per spec, trailing tokens after the declaration are ignored.
    def parse_declaration
      skip_whitespace

      parse_error!('expected a declaration') unless peek.type == :ident

      decl = try_consume_declaration

      parse_error!('invalid declaration') unless decl

      decl
    end

    # §5.4.4. Used for parsing the contents of a `style="..."` attribute,
    # `@page` blocks, and similar contexts where there is no enclosing `{}`.
    def parse_block_contents
      Block.new(items: collect_block_items(stop_at_close_brace: false))
    end

    # §5.3.7.
    def parse_component_value
      skip_whitespace

      parse_error!('expected a component value') if peek.type == :eof

      cv = consume_component_value

      skip_whitespace

      parse_error!("unexpected token after component value: #{peek.type}") unless peek.type == :eof

      cv
    end

    # §5.3.8.
    def parse_component_values
      values = []
      values << consume_component_value until peek.type == :eof
      values
    end

    # §5.3.9. Empty input produces `[[]]`; a trailing comma produces a
    # trailing empty group.
    def parse_comma_separated_values
      groups  = []
      current = []

      while true
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

    # Skips whitespace and (when comments are preserved) comment tokens.
    def skip_whitespace
      consume while peek.trivia?
    end

    # CDO/CDC tokens are dropped at the top level (legacy HTML wrapping);
    # inside a block they are treated as the start of a qualified rule.
    # Comment tokens are passed through into the rules list when present.
    def consume_rule_list(top_level:)
      rules = []

      while true
        t = peek

        case t.type
        when :eof
          return rules
        when :whitespace, :semicolon
          consume
        when :comment
          rules << consume
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

    def consume_at_rule(nested:)
      name    = consume.value
      prelude = []
      block   = nil

      while true
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

      strip_whitespace!(prelude)
      AtRule.new(name:, prelude:, block:)
    end

    # On EOF or a stop token (`}` while nested), the rule is dropped per
    # §5.4.3 — but already-consumed prelude tokens are NOT put back. Rewinding
    # would leave the caller's cursor at the same starting token and loop
    # forever on input like `style="hidden"` (no `:` and no `{`).
    def consume_qualified_rule(nested:)
      prelude = []

      while true
        t = peek

        case t.type
        when :eof
          return nil
        when :rbrace
          return nil if nested

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
          strip_whitespace!(prelude)
          return QualifiedRule.new(prelude:, block:)
        else
          prelude << consume_component_value
        end
      end
    end

    # Assumes the opening `{` has already been consumed; consumes through
    # the matching `}`.
    def consume_braced_block
      Block.new(items: collect_block_items(stop_at_close_brace: true))
    end

    # Shared loop for both `{}`-terminated blocks (inside a rule) and
    # EOF-terminated block contents (style attribute, `@page`, etc.).
    # Comment tokens are passed through into the items list when present.
    def collect_block_items(stop_at_close_brace:)
      items = []

      while true
        t = peek

        case t.type
        when :eof
          return items
        when :rbrace
          consume
          return items if stop_at_close_brace
          # Stray `}` outside any block: parse error per spec; skip.
          next
        when :whitespace, :semicolon
          consume
        when :comment
          items << consume
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

    # In nested context a token sequence like `a:hover { ... }` looks like
    # the start of a declaration (`<ident> : ...`). We detect such cases by
    # noticing a `{}` simple block in the value and rolling back so the
    # caller can re-parse it as a nested qualified rule.
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

      while true
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

      if value.any? { _1.is_a?(SimpleBlock) && _1.braced? }
        @pos = saved
        return nil
      end

      important = extract_important!(value)
      strip_whitespace!(value)

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
      open_type = consume.type
      open_char = BRACKET_OPEN_CHAR.fetch(open_type)
      end_type  = BRACKET_CLOSE_TYPE.fetch(open_type)
      values    = []

      while true
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

      while true
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

    # Strips only whitespace tokens — comments, when present, are preserved
    # as significant content of preludes/values.
    def strip_whitespace!(value)
      value.shift while whitespace_item?(value.first)
      value.pop   while whitespace_item?(value.last)
    end

    def whitespace_item?(item)
      item.is_a?(Token) && item.whitespace?
    end

    # Strips a trailing `! important` from `value` and returns whether it
    # was present.
    def extract_important!(value)
      i = value.length - 1
      i -= 1 while i >= 0 && trivia_item?(value[i])

      return false unless i >= 1

      ident = value[i]

      return false unless ident.is_a?(Token) && ident.type == :ident && ident.value.casecmp('important').zero?

      j = i - 1
      j -= 1 while j >= 0 && trivia_item?(value[j])

      bang = value[j]

      return false unless bang.is_a?(Token) && bang.type == :delim && bang.value == '!'

      value.slice!(j..)
      true
    end

    def trivia_item?(item)
      item.is_a?(Token) && item.trivia?
    end
  end
end
