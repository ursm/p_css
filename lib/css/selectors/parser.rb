module CSS
  module Selectors
    # Parser for CSS Selectors Level 4. Covers compound and complex
    # selectors, the four standard combinators (descendant, child, next-
    # sibling, subsequent-sibling), pseudo-classes / pseudo-elements
    # (with recursive parsing of `:not/:is/:where/:has` and AnB parsing of
    # `:nth-*`), attribute selectors with case-insensitive `i` / `s` flags,
    # and the `&` nesting selector.
    #
    # Out of scope (intermediate plan): namespace prefixes, the column
    # combinator `||`, and forgiving vs strict selector list distinctions.
    class Parser
      include CSS::TokenCursor

      SELECTOR_LIST_PSEUDOS = %w[is where not matches].freeze
      ANB_PSEUDOS           = %w[nth-child nth-last-child nth-of-type nth-last-of-type].freeze

      # Per the Selectors grammar (and every browser's querySelector), a known
      # pseudo-element is a valid selector that simply matches no element, while
      # an unknown one (`::example`) is a syntax error. Vendor-prefixed
      # `::-webkit-…` are accepted leniently since they match nothing.
      KNOWN_PSEUDO_ELEMENTS = %w[
        before after first-line first-letter
        marker placeholder selection backdrop file-selector-button
        target-text grammar-error spelling-error highlight
        cue cue-region part slotted details-content
        view-transition view-transition-group view-transition-image-pair
        view-transition-old view-transition-new
      ].to_set.freeze

      ATTR_MATCHERS = {
        '~' => :includes,
        '|' => :dash,
        '^' => :prefix,
        '$' => :suffix,
        '*' => :substring
      }.freeze

      class << self
        def parse_selector_list(input)
          new(tokens_from(input)).parse_selector_list_complete
        end

        def parse_selector(input)
          new(tokens_from(input)).parse_selector_complete
        end

        private

        def tokens_from(input)
          return Tokenizer.new(input).tokenize if input.is_a?(String)

          flatten_tokens(input.to_a)
        end

        # Selectors are normally parsed straight from a token stream, but a
        # caller may pass a `prelude` from the main parser, which contains
        # `Function` and `SimpleBlock` AST nodes in place of the raw paren
        # / bracket tokens. Flatten those back into a token sequence the
        # selector parser can step through.
        def flatten_tokens(items)
          out = []

          items.each {|it|
            case it
            when Token
              out << it
            when Nodes::SimpleBlock
              out << Token.new(BRACKET_TYPE_FOR_OPEN.fetch(it.open))
              out.concat(flatten_tokens(it.value))
              out << Token.new(BRACKET_CLOSE_TYPE_FOR_OPEN.fetch(it.open))
            when Nodes::Function
              out << Token.new(:function, it.name)
              out.concat(flatten_tokens(it.value))
              out << Token.new(:rparen)
            else
              raise ArgumentError, "cannot feed #{it.class} into selector parser"
            end
          }

          out
        end
      end

      BRACKET_TYPE_FOR_OPEN       = BRACKET_OPEN_CHAR.invert.freeze
      BRACKET_CLOSE_TYPE_FOR_OPEN = BRACKET_OPEN_CHAR.to_h {|type, ch| [ch, BRACKET_CLOSE_TYPE.fetch(type)] }.freeze

      def initialize(tokens)
        init_cursor(tokens)
      end

      def parse_selector_list_complete
        list = parse_selector_list

        skip_whitespace

        parse_error!("trailing tokens after selector list: #{peek.type}") unless peek.type == :eof

        list
      end

      def parse_selector_complete
        skip_whitespace

        cs = parse_complex_selector

        skip_whitespace

        parse_error!("trailing tokens after selector: #{peek.type}") unless peek.type == :eof

        cs
      end

      # A comma-separated list of complex selectors, terminated by EOF or
      # `)` (for use inside functional pseudos like `:is(...)`).
      def parse_selector_list
        skip_whitespace

        parse_error!('empty selector list') if list_terminator?(peek)

        selectors = [parse_complex_selector]

        loop do
          skip_whitespace
          break unless peek.type == :comma

          consume
          skip_whitespace
          selectors << parse_complex_selector
        end

        SelectorList.new(selectors:)
      end

      def parse_complex_selector
        skip_whitespace

        compounds   = [parse_compound_selector]
        combinators = []

        loop do
          combo = try_consume_combinator
          break if combo.nil?

          compounds   << parse_compound_selector
          combinators << combo
        end

        ComplexSelector.new(compounds:, combinators:)
      end

      private

      def consume_whitespace_returning_bool
        consumed = false

        while peek.type == :whitespace
          consume
          consumed = true
        end

        consumed
      end

      def list_terminator?(t)
        t.type == :eof || t.type == :rparen
      end

      def try_consume_combinator
        saved  = @pos
        had_ws = consume_whitespace_returning_bool

        t = peek

        if t.type == :delim && (combo = combinator_for_delim(t.value))
          consume
          skip_whitespace
          return combo
        end

        if had_ws && compound_selector_ahead?(t)
          return :descendant
        end

        @pos = saved
        nil
      end

      def combinator_for_delim(value)
        case value
        when '>' then :child
        when '+' then :next_sibling
        when '~' then :subsequent_sibling
        end
      end

      def compound_selector_ahead?(t)
        case t.type
        when :ident, :hash, :lbracket, :colon
          true
        when :delim
          %w[* . &].include?(t.value)
        else
          false
        end
      end

      def parse_compound_selector
        components = []

        if (head = try_consume_type_or_universal)
          components << head
        end

        loop do
          sub = try_consume_subclass_or_pseudo
          break if sub.nil?

          components << sub
        end

        parse_error!('expected a compound selector') if components.empty?

        CompoundSelector.new(components:)
      end

      def try_consume_type_or_universal
        case peek.type
        when :ident
          TypeSelector.new(name: consume.value)
        when :delim
          case peek.value
          when '*' then consume; UniversalSelector.new
          when '&' then consume; NestingSelector.new
          end
        end
      end

      def try_consume_subclass_or_pseudo
        case peek.type
        when :hash
          parse_id_selector
        when :lbracket
          parse_attribute_selector
        when :colon
          parse_pseudo
        when :delim
          case peek.value
          when '.' then parse_class_selector
          when '&' then consume; NestingSelector.new
          end
        end
      end

      def parse_id_selector
        t = consume

        parse_error!('id hash must be a valid identifier') unless t.flag == :id

        IdSelector.new(name: t.value)
      end

      def parse_class_selector
        consume # the '.'

        parse_error!("expected ident after '.', got #{peek.type}") unless peek.type == :ident

        ClassSelector.new(name: consume.value)
      end

      def parse_attribute_selector
        consume # [
        skip_whitespace

        parse_error!('expected attribute name') unless peek.type == :ident

        name = consume.value

        skip_whitespace

        matcher, value = parse_attr_matcher_and_value
        case_flag      = parse_attr_case_flag

        skip_whitespace

        parse_error!("expected ']', got #{peek.type}") unless peek.type == :rbracket

        consume

        AttributeSelector.new(name:, matcher:, value:, case_flag:)
      end

      def parse_attr_matcher_and_value
        return [nil, nil] if peek.type == :rbracket

        matcher =
          if peek.type == :delim && peek.value == '='
            consume
            :exact
          elsif peek.type == :delim && (sym = ATTR_MATCHERS[peek.value])
            consume
            unless peek.type == :delim && peek.value == '='
              parse_error!("expected '=' to complete attribute matcher")
            end
            consume
            sym
          else
            parse_error!("invalid attribute matcher: #{peek.type}")
          end

        skip_whitespace

        unless peek.type == :ident || peek.type == :string
          parse_error!("expected attribute value, got #{peek.type}")
        end

        [matcher, consume.value]
      end

      def parse_attr_case_flag
        skip_whitespace

        return nil unless peek.type == :ident

        v = peek.value.downcase
        return nil unless v == 'i' || v == 's'

        consume
        v.to_sym
      end

      def parse_pseudo
        consume # first colon

        if peek.type == :colon
          consume
          parse_pseudo_body(element: true)
        else
          parse_pseudo_body(element: false)
        end
      end

      def parse_pseudo_body(element:)
        head = peek.type

        unless head == :ident || head == :function
          parse_error!("expected pseudo-#{element ? 'element' : 'class'} name, got #{head}")
        end

        name = consume.value

        if element && !known_pseudo_element?(name)
          parse_error!("unknown pseudo-element ::#{name}")
        end

        return build_pseudo(element:, name:, argument: nil) if head == :ident

        arg = parse_pseudo_argument(name)

        parse_error!("expected ')' to close :#{name}") unless peek.type == :rparen

        consume
        build_pseudo(element:, name:, argument: arg)
      end

      def known_pseudo_element?(name)
        n = name.downcase
        n.start_with?('-') || KNOWN_PSEUDO_ELEMENTS.include?(n)
      end

      def build_pseudo(element:, name:, argument:)
        element ? PseudoElement.new(name:, argument:) : PseudoClass.new(name:, argument:)
      end

      def parse_pseudo_argument(name)
        n = name.downcase

        if SELECTOR_LIST_PSEUDOS.include?(n)
          parse_selector_list
        elsif n == 'has'
          parse_relative_selector_list
        elsif ANB_PSEUDOS.include?(n)
          parse_nth_argument(allow_of: n == 'nth-child' || n == 'nth-last-child')
        else
          collect_argument_tokens
        end
      end

      # `:nth-*` argument: An+B, optionally followed by `of <selector-list>`
      # (Selectors-4, only on `:nth-child` / `:nth-last-child`). Collects the
      # An+B tokens up to a top-level `of` ident, then parses S inline.
      def parse_nth_argument(allow_of:)
        anb_tokens = []
        depth      = 0

        loop do
          t = peek

          parse_error!('unexpected EOF in :nth argument') if t.type == :eof

          if depth.zero?
            break if t.type == :rparen
            break if allow_of && t.type == :ident && t.value.downcase == 'of'
          end

          case t.type
          when :function, :lparen then depth += 1
          when :rparen            then depth -= 1
          end

          anb_tokens << consume
        end

        anb = AnBParser.parse(anb_tokens)

        return anb unless allow_of && peek.type == :ident && peek.value.downcase == 'of'

        consume # `of`
        skip_whitespace
        AnB.new(step: anb.step, offset: anb.offset, of: parse_selector_list)
      end

      # `:has()` argument: a comma-separated list of relative selectors, each
      # an optional leading combinator (`>`, `+`, `~`; default descendant)
      # followed by a complex selector. Terminated by EOF or the closing `)`.
      def parse_relative_selector_list
        skip_whitespace

        parse_error!('empty :has() argument') if list_terminator?(peek)

        selectors = [parse_relative_selector]

        loop do
          skip_whitespace
          break unless peek.type == :comma

          consume
          skip_whitespace
          selectors << parse_relative_selector
        end

        RelativeSelectorList.new(selectors:)
      end

      def parse_relative_selector
        skip_whitespace

        combinator = :descendant

        t = peek

        if t.type == :delim && (combo = combinator_for_delim(t.value))
          combinator = combo
          consume
          skip_whitespace
        end

        RelativeSelector.new(combinator:, complex: parse_complex_selector)
      end

      # Collects all tokens up to the closing `)` of the current functional
      # context, balancing nested parens / functions.
      def collect_argument_tokens
        inner = []
        depth = 0

        loop do
          case peek.type
          when :eof
            parse_error!('unexpected EOF in pseudo argument')
          when :function, :lparen
            depth += 1
            inner << consume
          when :rparen
            break if depth.zero?

            depth -= 1
            inner << consume
          else
            inner << consume
          end
        end

        inner
      end
    end
  end
end
