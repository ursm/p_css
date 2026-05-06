module CSS
  module Selectors
    # Selectors §16 specificity tuple `(a, b, c)`.
    #   a = id selectors
    #   b = class / attribute / pseudo-class selectors
    #   c = type / pseudo-element selectors
    Specificity = Data.define(:a, :b, :c) do
      include Comparable

      # Avoids the per-call allocation of two 3-element arrays — this
      # comparison runs many times in the cascade-sort hot path.
      def <=>(other)
        return nil unless other.is_a?(Specificity)

        d = a - other.a
        return d unless d.zero?

        d = b - other.b
        return d unless d.zero?

        c - other.c
      end

      def +(other)
        Specificity.new(a: a + other.a, b: b + other.b, c: c + other.c)
      end

      def to_s = "#{a},#{b},#{c}"
    end

    Specificity::ZERO = Specificity.new(a: 0, b: 0, c: 0).freeze

    # Computes specificity for any selector AST node.
    #
    # Note on the nesting selector (`&`): without parent context its
    # specificity is conservatively reported as zero. Callers wanting
    # accurate cascade behavior should run `CSS.desugar(stylesheet)` first
    # so `&` is replaced by the parent's compounds.
    module SpecificityCalculator
      extend self

      def calculate(node)
        case node
        when SelectorList     then node.selectors.map { calculate(it) }.max || Specificity::ZERO
        when ComplexSelector  then sum(node.compounds)
        when CompoundSelector then sum(node.components)
        when IdSelector       then Specificity.new(a: 1, b: 0, c: 0)
        when ClassSelector,
             AttributeSelector then Specificity.new(a: 0, b: 1, c: 0)
        when TypeSelector     then Specificity.new(a: 0, b: 0, c: 1)
        when PseudoElement    then Specificity.new(a: 0, b: 0, c: 1)
        when PseudoClass      then specificity_of_pseudo_class(node)
        when UniversalSelector,
             NestingSelector  then Specificity::ZERO
        else                       Specificity::ZERO
        end
      end

      private

      def sum(items)
        items.map { calculate(it) }.reduce(Specificity::ZERO, :+)
      end

      def specificity_of_pseudo_class(node)
        case node.name.downcase
        when 'where'
          Specificity::ZERO
        when 'is', 'not', 'has', 'matches'
          if node.argument.is_a?(SelectorList)
            calculate(node.argument)
          else
            Specificity.new(a: 0, b: 1, c: 0)
          end
        else
          Specificity.new(a: 0, b: 1, c: 0)
        end
      end
    end
  end
end
