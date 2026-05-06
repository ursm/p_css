module CSS
  # Resolves the cascade for a Stylesheet against a single element. Returns
  # `Hash<String, Declaration>` keyed by property name with the winning
  # declaration after applying:
  #
  #   - `@media` filtering (against a `MediaQueries::Context`)
  #   - selector matching (`Selectors::Matcher`)
  #   - cascade sort: `!important` > origin / inline > specificity > source order
  #
  # The Stylesheet is compiled once on construction (selectors are
  # pre-parsed, specificities pre-computed, and `@media` chains are
  # evaluated against the supplied context up-front so non-matching rules
  # are dropped). `resolve(element)` is then cheap to call per node.
  #
  # Cascade layers, `@scope` proximity, and Shadow DOM encapsulation are
  # not modeled — `@layer`, `@supports`, `@container`, `@scope`, and
  # `@starting-style` blocks are descended into unconditionally.
  class Cascade
    Match = Data.define(:declaration, :specificity, :inline, :order)

    RuleEntry = Data.define(:selector_pairs, :declarations)

    TRANSPARENT_AT_RULES = %w[supports layer scope starting-style container].freeze

    def initialize(stylesheet, context: MediaQueries::Context.default)
      @context = context
      @entries = compile(stylesheet)
    end

    # Returns Hash<String, Declaration> of winning declarations.
    def resolve(element, inline_style: nil)
      order   = 0
      matches = []

      @entries.each do |entry|
        spec = best_matching_specificity(element, entry.selector_pairs)
        next if spec.nil?

        entry.declarations.each do |decl|
          order += 1
          matches << Match.new(declaration: decl, specificity: spec, inline: false, order: order)
        end
      end

      if inline_style
        inline_declarations(inline_style).each do |decl|
          order += 1
          matches << Match.new(declaration: decl, specificity: Selectors::Specificity::ZERO, inline: true, order: order)
        end
      end

      pick_winners(matches)
    end

    private

    def compile(stylesheet)
      out = []
      walk(stylesheet.rules, [], out)
      out
    end

    # Filters the stylesheet down to rules whose `@media` chain (if any)
    # matches the cascade's context, pre-parsing every selector list and
    # caching its specificity per selector.
    def walk(rules, media_chain, out)
      rules.each do |rule|
        case rule
        when Nodes::QualifiedRule
          register_qualified_rule(rule, media_chain, out)
        when Nodes::AtRule
          dispatch_at_rule(rule, media_chain, out)
        end
      end
    end

    def register_qualified_rule(rule, media_chain, out)
      return unless media_chain.all? { MediaQueries::Evaluator.evaluate(it, @context) }

      sl = Selectors::Parser.parse_selector_list(rule.prelude)
      pairs = sl.selectors.map { [it, Selectors::SpecificityCalculator.calculate(it)] }
      decls = rule.block.items.select { it.is_a?(Nodes::Declaration) }

      out << RuleEntry.new(selector_pairs: pairs, declarations: decls)
    rescue ParseError
      # Browsers drop a rule whose prelude doesn't parse as a selector
      # list rather than poisoning the whole stylesheet; do the same.
    end

    def dispatch_at_rule(rule, media_chain, out)
      return unless rule.block

      case rule.name.downcase
      when 'media'
        ql = MediaQueries::Parser.parse(rule.prelude)
        walk(rule.block.items, [*media_chain, ql], out)
      when *TRANSPARENT_AT_RULES
        walk(rule.block.items, media_chain, out)
      end
    rescue ParseError
      # Bad media prelude → skip this @media block; rules outside it
      # remain unaffected.
    end

    def best_matching_specificity(element, selector_pairs)
      best = nil

      selector_pairs.each do |sel, spec|
        next unless Selectors::Matcher.matches?(element, sel)

        best = spec if best.nil? || spec > best
      end

      best
    end

    # Single-pass: keep the running winner per property name. Cheaper than
    # group_by + max_by, and more importantly avoids allocating a fresh
    # comparison key per declaration.
    def pick_winners(matches)
      winners       = {}
      winner_matches = {}

      matches.each do |m|
        name      = m.declaration.name
        incumbent = winner_matches[name]

        if incumbent.nil? || better?(m, incumbent)
          winners[name]        = m.declaration
          winner_matches[name] = m
        end
      end

      winners
    end

    # `m` outranks `incumbent` when its priority class is higher, or — at
    # the same priority class — its specificity is greater, or — at equal
    # specificity — it appeared later in source order.
    def better?(m, incumbent)
      a = priority(m)
      b = priority(incumbent)
      return a > b unless a == b

      cmp = m.specificity <=> incumbent.specificity
      return cmp.positive? unless cmp.zero?

      m.order > incumbent.order
    end

    # !important and inline style each bump the rule into a higher
    # priority class. Encoded so that `priority(a) <=> priority(b)`
    # captures the cascade's origin/importance ordering.
    def priority(m)
      (m.declaration.important ? 2 : 0) + (m.inline ? 1 : 0)
    end

    def inline_declarations(style)
      case style
      when String       then CSS.parse_block_contents(style).items.select { it.is_a?(Nodes::Declaration) }
      when Nodes::Block then style.items.select { it.is_a?(Nodes::Declaration) }
      when Array        then style.select        { it.is_a?(Nodes::Declaration) }
      else
        raise ArgumentError, "cannot derive inline declarations from #{style.class}"
      end
    end
  end
end
