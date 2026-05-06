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
  # pre-parsed, specificities pre-computed, `@media` chains are
  # evaluated against the supplied context up-front, and rules are
  # indexed by the rightmost compound's strongest anchor — id > class >
  # tag > universal). `resolve(element)` then visits only the rules whose
  # anchor could match the element.
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
      @index   = build_index(@entries)
    end

    # Returns Hash<String, Declaration> of winning declarations.
    def resolve(element, inline_style: nil)
      cache       = {}
      candidates  = collect_candidate_indexes(element, cache)
      order       = 0
      matches     = []

      candidates.each do |idx|
        entry = @entries[idx]
        spec  = best_matching_specificity(element, entry.selector_pairs, cache)

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

    # Compile
    # ----------------------------------------------------------------

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

      sl    = Selectors::Parser.parse_selector_list(rule.prelude)
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

    # Index
    # ----------------------------------------------------------------

    Index = Data.define(:by_id, :by_class, :by_tag, :universal)

    EMPTY_INDEXES = [].freeze

    def build_index(entries)
      by_id     = {}
      by_class  = {}
      by_tag    = {}
      universal = []

      entries.each_with_index do |entry, idx|
        keys = Set.new

        entry.selector_pairs.each do |sel, _spec|
          key = anchor_key(sel)

          next if keys.include?(key)

          keys << key

          case key.first
          when :id        then (by_id[key.last]    ||= []) << idx
          when :class     then (by_class[key.last] ||= []) << idx
          when :tag       then (by_tag[key.last]   ||= []) << idx
          when :universal then universal                   << idx
          end
        end
      end

      Index.new(
        by_id:     by_id.freeze,
        by_class:  by_class.freeze,
        by_tag:    by_tag.freeze,
        universal: universal.freeze
      )
    end

    # Picks the strongest anchor in the rightmost compound: id > class >
    # tag > universal. Compounds whose only simple selectors are pseudos
    # (e.g. `:hover`) or attribute matchers fall through to universal —
    # they will be tested against every element, but real-world
    # stylesheets rarely have many such rules.
    def anchor_key(complex_selector)
      compound = complex_selector.compounds.last

      compound.components.each do |c|
        return [:id, c.name] if c.is_a?(Selectors::IdSelector)
      end
      compound.components.each do |c|
        return [:class, c.name] if c.is_a?(Selectors::ClassSelector)
      end
      compound.components.each do |c|
        return [:tag, c.name.downcase] if c.is_a?(Selectors::TypeSelector)
      end

      [:universal]
    end

    # Resolve helpers
    # ----------------------------------------------------------------

    def collect_candidate_indexes(element, cache)
      seen = Set.new

      el_id = Selectors::Matcher.id_of(element, cache)

      if el_id && (bucket = @index.by_id[el_id])
        seen.merge(bucket)
      end

      Selectors::Matcher.classes_of(element, cache).each do |cls|
        bucket = @index.by_class[cls]
        seen.merge(bucket) if bucket
      end

      tag_bucket = @index.by_tag[Selectors::Matcher.tag_of(element, cache)]
      seen.merge(tag_bucket) if tag_bucket

      seen.merge(@index.universal)

      seen.to_a.sort!
    end

    def best_matching_specificity(element, selector_pairs, cache)
      best = nil

      selector_pairs.each do |sel, spec|
        next unless Selectors::Matcher.matches?(element, sel, cache: cache)

        best = spec if best.nil? || spec > best
      end

      best
    end

    # Single-pass running max per property name. Cheaper than group_by +
    # max_by, and avoids allocating a fresh comparison key per
    # declaration.
    def pick_winners(matches)
      best = {}

      matches.each do |m|
        name      = m.declaration.name
        incumbent = best[name]

        best[name] = m if incumbent.nil? || better?(m, incumbent)
      end

      best.transform_values(&:declaration)
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
