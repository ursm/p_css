module CSS
  # Desugars CSS Nesting Module Level 1 — replaces `&` with the parent
  # selector and lifts every nested rule out of its parent. The result is
  # a flat Stylesheet whose rules contain only declarations and at-rules.
  #
  # The substitution favors readable output over conservative correctness
  # padding: `:is(parent)` wrapping is only emitted when the parent has
  # multiple selectors, or when a non-lone `&` is mixed into a compound and
  # the parent has combinators. In simple cases the parent is inlined
  # directly (`& .x` with parent `.a` → `.a .x`, not `:is(.a) .x`).
  module Nesting
    extend self

    def desugar(stylesheet)
      Nodes::Stylesheet.new(rules: stylesheet.rules.flat_map { desugar_top_level(it) })
    end

    private

    def desugar_top_level(rule)
      case rule
      when Nodes::QualifiedRule
        desugar_qualified_rule(rule, parent_list: nil)
      when Nodes::AtRule
        [desugar_at_rule(rule, parent_list: nil)]
      else
        [rule]
      end
    end

    # Returns an Array of rules. The first emitted rule (when there are
    # declarations) carries the parent's own declarations under the
    # effective selector; subsequent rules are the nested ones recursively
    # desugared.
    def desugar_qualified_rule(rule, parent_list:)
      own       = Selectors::Parser.parse_selector_list(rule.prelude)
      effective = parent_list ? substitute_nesting(own, parent_list) : own

      decls, rules = partition_block_items(rule.block.items, parent_list: effective)

      output = []
      output << build_rule_with(effective, decls) unless decls.empty?
      output.concat(rules)
      output
    end

    # Desugars a top-level (or nested) at-rule, recursing into its block
    # if any.
    def desugar_at_rule(rule, parent_list:)
      return rule unless rule.block

      new_items = desugar_at_rule_block_items(rule.block.items, parent_list:)

      Nodes::AtRule.new(
        name:    rule.name,
        prelude: rule.prelude,
        block:   Nodes::Block.new(items: new_items)
      )
    end

    # Inside an at-rule's block (e.g. `@media`), declarations need to be
    # wrapped in a synthesized rule using the parent selector if there is
    # one (the at-rule itself doesn't carry a selector).
    def desugar_at_rule_block_items(items, parent_list:)
      decls, rules = partition_block_items(items, parent_list:)

      output = []

      unless decls.empty?
        if parent_list
          output << build_rule_with(parent_list, decls)
        else
          output.concat(decls)
        end
      end

      output.concat(rules)
      output
    end

    # Splits items into (declarations, nested rules). Nested qualified
    # rules and at-rules are recursively desugared.
    def partition_block_items(items, parent_list:)
      decls = []
      rules = []

      items.each {|item|
        case item
        when Nodes::Declaration
          decls << item
        when Nodes::QualifiedRule
          rules.concat(desugar_qualified_rule(item, parent_list:))
        when Nodes::AtRule
          rules << desugar_at_rule(item, parent_list:)
        else
          decls << item
        end
      }

      [decls, rules]
    end

    def build_rule_with(selector_list, items)
      Nodes::QualifiedRule.new(
        prelude: Parser.parse_component_values(Selectors::Serializer.serialize(selector_list)),
        block:   Nodes::Block.new(items:)
      )
    end

    # Substitution
    # ----------------------------------------------------------------

    def substitute_nesting(own_list, parent_list)
      Selectors::SelectorList.new(
        selectors: own_list.selectors.map {|sel|
          substitute_complex(ensure_nesting(sel), parent_list)
        }
      )
    end

    # Per CSS Nesting §3.1, a selector that doesn't reference `&` has it
    # implicitly prepended with the descendant combinator. `.b` becomes
    # `& .b`.
    def ensure_nesting(complex_selector)
      return complex_selector if contains_nesting?(complex_selector)

      Selectors::ComplexSelector.new(
        compounds:   [
          Selectors::CompoundSelector.new(components: [Selectors::NestingSelector.new]),
          *complex_selector.compounds
        ],
        combinators: [:descendant, *complex_selector.combinators]
      )
    end

    def contains_nesting?(complex_selector)
      complex_selector.compounds.any? {|c|
        c.components.any? { it.is_a?(Selectors::NestingSelector) }
      }
    end

    def substitute_complex(own_complex, parent_list)
      if parent_list.selectors.size > 1
        substitute_with_is(own_complex, parent_list)
      else
        parent = parent_list.selectors.first

        if parent.compounds.size > 1
          substitute_inline_compounds(own_complex, parent, parent_list)
        else
          substitute_inline_components(own_complex, parent.compounds.first)
        end
      end
    end

    # Multi-selector parent: every `&` becomes `:is(parent_list)`, regardless
    # of the surrounding compound shape.
    def substitute_with_is(own_complex, parent_list)
      replacement = Selectors::PseudoClass.new(name: 'is', argument: parent_list)

      Selectors::ComplexSelector.new(
        compounds:   own_complex.compounds.map { swap_components_in_compound(it, replacement) },
        combinators: own_complex.combinators
      )
    end

    # Single complex parent with multiple compounds: a lone `&` compound is
    # spliced in by the parent's compound chain (carrying combinators);
    # mixed compounds use `:is()` wrapping.
    def substitute_inline_compounds(own_complex, parent_complex, parent_list)
      replacement   = Selectors::PseudoClass.new(name: 'is', argument: parent_list)
      new_compounds = []
      new_combos    = []
      pair_combos   = [nil, *own_complex.combinators]

      own_complex.compounds.each_with_index {|compound, i|
        incoming = pair_combos[i]

        if lone_nesting?(compound)
          parent_complex.compounds.each_with_index {|pc, j|
            new_compounds << pc

            if j.zero?
              new_combos << incoming unless incoming.nil?
            else
              new_combos << parent_complex.combinators[j - 1]
            end
          }
        else
          new_compounds << swap_components_in_compound(compound, replacement)
          new_combos << incoming unless incoming.nil?
        end
      }

      Selectors::ComplexSelector.new(compounds: new_compounds, combinators: new_combos)
    end

    # Single compound parent: components are spliced in place of `&`,
    # producing a clean compound (`&.x` with parent `.a` → `.a.x`).
    def substitute_inline_components(own_complex, parent_compound)
      Selectors::ComplexSelector.new(
        compounds:   own_complex.compounds.map {|compound|
          if lone_nesting?(compound)
            Selectors::CompoundSelector.new(components: parent_compound.components.dup)
          else
            Selectors::CompoundSelector.new(
              components: compound.components.flat_map {|x|
                x.is_a?(Selectors::NestingSelector) ? parent_compound.components : [x]
              }
            )
          end
        },
        combinators: own_complex.combinators
      )
    end

    def swap_components_in_compound(compound, replacement)
      Selectors::CompoundSelector.new(
        components: compound.components.map {|x|
          x.is_a?(Selectors::NestingSelector) ? replacement : x
        }
      )
    end

    def lone_nesting?(compound)
      compound.components.size == 1 && compound.components.first.is_a?(Selectors::NestingSelector)
    end
  end
end
