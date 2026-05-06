module CSS
  # Resolves the cascade for a Stylesheet against a single element. Returns
  # `Hash<String, Declaration>` keyed by property name with the winning
  # declaration after applying:
  #
  #   - `@media` filtering (against a `MediaQueries::Context`)
  #   - selector matching (`Selectors::Matcher`)
  #   - cascade sort: `!important` > origin / inline > specificity > source order
  #
  # The Stylesheet is compiled once on construction (selectors and media
  # queries are pre-parsed); `resolve(element)` is cheap to call per node.
  #
  # Cascade layers, `@scope` proximity, and Shadow DOM encapsulation are
  # not modeled — `@layer`, `@supports`, `@container`, `@scope`, and
  # `@starting-style` blocks are descended into unconditionally.
  class Cascade
    RuleEntry = Data.define(:selector_list, :declarations, :media_chain)

    TRANSPARENT_AT_RULES = %w[supports layer scope starting-style container].freeze

    def initialize(stylesheet, context: MediaQueries::Context.default)
      @context = context
      @entries = compile(stylesheet)
    end

    # Returns Hash<String, Declaration> of winning declarations.
    def resolve(element, inline_style: nil)
      order   = 0
      matches = []

      @entries.each {|entry|
        next unless entry.media_chain.all? { MediaQueries::Evaluator.evaluate(it, @context) }

        spec = best_matching_specificity(element, entry.selector_list)
        next if spec.nil?

        entry.declarations.each {|decl|
          order += 1
          matches << [decl, spec, false, order]
        }
      }

      if inline_style
        inline_declarations(inline_style).each {|decl|
          order += 1
          matches << [decl, Selectors::Specificity::ZERO, true, order]
        }
      end

      pick_winners(matches)
    end

    private

    def compile(stylesheet)
      out = []
      walk(stylesheet.rules, [], out)
      out
    end

    def walk(rules, media_chain, out)
      rules.each {|rule|
        case rule
        when Nodes::QualifiedRule
          register_qualified_rule(rule, media_chain, out)
        when Nodes::AtRule
          dispatch_at_rule(rule, media_chain, out)
        end
      }
    end

    def register_qualified_rule(rule, media_chain, out)
      sl = Selectors::Parser.parse_selector_list(rule.prelude)
      decls = rule.block.items.select { it.is_a?(Nodes::Declaration) }
      out << RuleEntry.new(selector_list: sl, declarations: decls, media_chain: media_chain)
    rescue ParseError
      # Invalid selector list — skip the rule rather than poisoning the
      # whole stylesheet (browsers do the same).
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
      # Bad media prelude → skip this @media block.
    end

    def best_matching_specificity(element, selector_list)
      best = nil

      selector_list.selectors.each {|sel|
        next unless Selectors::Matcher.matches?(element, sel)

        spec = Selectors::SpecificityCalculator.calculate(sel)
        best = spec if best.nil? || spec > best
      }

      best
    end

    def pick_winners(matches)
      winners = {}

      matches.group_by { it[0].name }.each {|name, ms|
        winner = ms.max_by {|decl, spec, inline, order|
          [decl.important ? 1 : 0, inline ? 1 : 0, spec, order]
        }
        winners[name] = winner[0]
      }

      winners
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
