module CSS
  module MediaQueries
    # Parser for `<media-query-list>` per Media Queries Level 4 §3.
    # https://drafts.csswg.org/mediaqueries-4/
    #
    # Accepts either a String (which is tokenized and re-component-valued
    # so `(...)` becomes a `SimpleBlock`) or an Array of component values
    # (for use against an `@media` rule's prelude from the main parser).
    class Parser
      include CSS::TokenCursor

      MODIFIER_KEYWORDS = %w[not only].freeze
      LOGICAL_KEYWORDS  = %w[and or not].freeze

      class << self
        def parse(input)
          new(items_from(input)).parse_media_query_list
        end

        private

        def items_from(input)
          input.is_a?(String) ? CSS::Parser.parse_component_values(input) : input.to_a
        end
      end

      def initialize(items)
        init_cursor(items)
      end

      def parse_media_query_list
        skip_whitespace

        queries = [parse_media_query]

        loop do
          skip_whitespace
          break unless peek_token.type == :comma

          consume
          queries << parse_media_query
        end

        skip_whitespace

        unless eof?
          parse_error!("trailing tokens after media query list: #{describe(peek)}")
        end

        MediaQueryList.new(queries:)
      end

      def parse_media_query
        skip_whitespace

        saved = @pos

        # Try the `[not | only]? <media-type> [and <condition-without-or>]?` form.
        modifier = consume_modifier
        skip_whitespace if modifier

        if (item = peek).is_a?(Token) && item.type == :ident && !LOGICAL_KEYWORDS.include?(item.value.downcase)
          type = consume.value.downcase
          skip_whitespace

          condition = nil

          if keyword?('and')
            consume
            skip_whitespace
            condition = parse_media_condition(allow_or: false)
          end

          return MediaQuery.new(modifier:, type:, condition:)
        end

        # Otherwise this is a pure media-condition (no type / modifier).
        @pos = saved

        MediaQuery.new(modifier: nil, type: nil, condition: parse_media_condition(allow_or: true))
      end

      private

      def parse_media_condition(allow_or:)
        skip_whitespace

        if keyword?('not')
          consume
          skip_whitespace
          return MediaNot.new(operand: parse_media_in_parens)
        end

        first = parse_media_in_parens

        skip_whitespace

        if keyword?('and')
          operands = [first]
          while keyword?('and')
            consume
            skip_whitespace
            operands << parse_media_in_parens
            skip_whitespace
          end
          MediaAnd.new(operands:)
        elsif allow_or && keyword?('or')
          operands = [first]
          while keyword?('or')
            consume
            skip_whitespace
            operands << parse_media_in_parens
            skip_whitespace
          end
          MediaOr.new(operands:)
        else
          first
        end
      end

      def parse_media_in_parens
        item = peek

        unless item.is_a?(Nodes::SimpleBlock) && item.parenthesized?
          parse_error!("expected '(', got #{describe(item)}")
        end

        consume
        inner = self.class.new(item.value)
        inner.parse_in_parens_contents
      end

      protected

      # Called on a sub-parser whose @items is the contents inside `(...)`.
      # Returns a media-condition or a feature.
      def parse_in_parens_contents
        skip_whitespace

        return GeneralEnclosed.new(tokens: []) if eof?

        # Nested `(condition)`?
        first = peek

        if first.is_a?(Nodes::SimpleBlock) && first.parenthesized?
          cond = parse_media_condition(allow_or: true)
          skip_whitespace

          unless eof?
            return GeneralEnclosed.new(tokens: @items)
          end

          return cond
        end

        result = try_parse_feature

        return result if result

        GeneralEnclosed.new(tokens: @items)
      end

      private

      def try_parse_feature
        saved = @pos

        starting_token = peek

        if starting_token.is_a?(Token) && starting_token.type == :ident
          feature = try_parse_feature_starting_with_ident

          return feature if feature

          @pos = saved
        end

        if value_starts?(starting_token)
          feature = try_parse_feature_starting_with_value

          return feature if feature

          @pos = saved
        end

        nil
      end

      def try_parse_feature_starting_with_ident
        name = consume.value.downcase

        skip_whitespace

        if eof?
          return MediaFeature.new(name:, op: nil, value: nil)
        end

        if peek_token.type == :colon
          consume
          skip_whitespace
          value = parse_mf_value

          return nil if value.nil?

          skip_whitespace

          return nil unless eof?

          return MediaFeature.new(name:, op: :eq, value:)
        end

        if (op = consume_comparison)
          skip_whitespace
          value = parse_mf_value

          return nil if value.nil?

          skip_whitespace

          if eof?
            return MediaFeature.new(name:, op:, value:)
          end

          # Bounded form: `<name> <op> <value> ... <op> <value>`
          # Per spec, bounded form has the name in the middle, not here.
          # Reject.
          return nil
        end

        nil
      end

      def try_parse_feature_starting_with_value
        first_value = parse_mf_value

        return nil if first_value.nil?

        skip_whitespace

        first_op = consume_comparison

        return nil unless first_op

        skip_whitespace

        return nil unless peek_token.type == :ident

        name = consume.value.downcase

        skip_whitespace

        if eof?
          return MediaFeature.new(name:, op: invert_op(first_op), value: first_value)
        end

        # Bounded form: <value> <op1> <name> <op2> <value>
        second_op = consume_comparison

        return nil unless second_op

        skip_whitespace

        second_value = parse_mf_value

        return nil if second_value.nil?

        skip_whitespace

        return nil unless eof?

        # Decompose into MediaAnd of two normalized features.
        MediaAnd.new(operands: [
          MediaFeature.new(name:, op: invert_op(first_op), value: first_value),
          MediaFeature.new(name:, op: second_op,           value: second_value)
        ])
      end

      # `value op name` swaps to `name (inverted op) value`.
      INVERSE_OP = {lt: :gt, le: :ge, gt: :lt, ge: :le, eq: :eq}.freeze

      def invert_op(op) = INVERSE_OP.fetch(op, op)

      def parse_mf_value
        item = peek

        return nil unless item.is_a?(Token)

        case item.type
        when :number
          consume

          if peek_token.type == :delim && peek_token.value == '/'
            consume
            skip_whitespace
            denom = peek

            return nil unless denom.is_a?(Token) && denom.type == :number

            consume
            return Ratio.new(numerator: item.value, denominator: denom.value)
          end

          item
        when :dimension, :percentage, :ident, :string
          consume
          item
        else
          nil
        end
      end

      def consume_comparison
        item = peek

        return nil unless item.is_a?(Token) && item.type == :delim

        case item.value
        when '='
          consume
          :eq
        when '<'
          consume

          if peek_token.type == :delim && peek_token.value == '='
            consume
            :le
          else
            :lt
          end
        when '>'
          consume

          if peek_token.type == :delim && peek_token.value == '='
            consume
            :ge
          else
            :gt
          end
        end
      end

      def value_starts?(item)
        item.is_a?(Token) && %i[number dimension percentage].include?(item.type)
      end

      def consume_modifier
        item = peek

        return nil unless item.is_a?(Token) && item.type == :ident

        kw = item.value.downcase

        return nil unless MODIFIER_KEYWORDS.include?(kw)

        consume
        kw.to_sym
      end

      def keyword?(kw)
        item = peek
        item.is_a?(Token) && item.type == :ident && item.value.downcase == kw
      end

      def describe(item)
        case item
        when Token             then item.type
        when Nodes::SimpleBlock then "#{item.open}-block"
        when Nodes::Function    then "#{item.name}()"
        else                        item.class.name
        end
      end
    end
  end
end
