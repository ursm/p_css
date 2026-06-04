module CSS
  module Selectors
    # Marker module included by every selector AST data class. Used by the
    # main `CSS.serialize` to dispatch into `Selectors::Serializer`.
    module Node; end

    # A comma-separated list of complex selectors.
    SelectorList = Data.define(:selectors) do
      include Node
      def to_s = Selectors::Serializer.serialize(self)
    end

    # Compounds connected by combinators. `compounds.size == combinators.size + 1`.
    # `combinators[i]` connects `compounds[i]` to `compounds[i + 1]`.
    ComplexSelector = Data.define(:compounds, :combinators) do
      include Node
      def to_s = Selectors::Serializer.serialize(self)
    end

    # A run of simple selectors with no combinators between them, e.g.
    # `a.foo:hover` or `[href]:not(:visited)`.
    CompoundSelector = Data.define(:components) do
      include Node
      def to_s = Selectors::Serializer.serialize(self)
    end

    TypeSelector      = Data.define(:name)        { include Node }
    UniversalSelector = Data.define              { include Node }
    NestingSelector   = Data.define              { include Node }
    IdSelector        = Data.define(:name)        { include Node }
    ClassSelector     = Data.define(:name)        { include Node }

    # Attribute matchers:
    #   nil         — `[name]` (presence)
    #   :exact      — `[a=b]`
    #   :includes   — `[a~=b]`
    #   :dash       — `[a|=b]`
    #   :prefix     — `[a^=b]`
    #   :suffix     — `[a$=b]`
    #   :substring  — `[a*=b]`
    #
    # `case_flag` is `nil`, `:i`, or `:s`.
    AttributeSelector = Data.define(:name, :matcher, :value, :case_flag) do
      include Node
    end

    # `argument` is `nil`, a `SelectorList` (`:not/:is/:where/:has`), an
    # `AnB` (`:nth-*`), or a raw `Array<Token>` for unrecognized functional
    # pseudos.
    PseudoClass   = Data.define(:name, :argument) { include Node }
    PseudoElement = Data.define(:name, :argument) { include Node }

    # `An+B` integer pair. `step` is the `n` coefficient, `offset` is the
    # constant term. `even` => AnB(2, 0), `odd` => AnB(2, 1), `5` => AnB(0, 5),
    # `n` => AnB(1, 0). `of` is the optional `of S` filter (a `SelectorList`),
    # `nil` except on `:nth-child` / `:nth-last-child`.
    AnB = Data.define(:step, :offset, :of) do
      include Node

      def initialize(step:, offset:, of: nil)
        super
      end

      def to_s = Selectors::Serializer.serialize(self)
    end

    # The argument of `:has()` — a comma-separated list of relative selectors.
    RelativeSelectorList = Data.define(:selectors) do
      include Node
      def to_s = Selectors::Serializer.serialize(self)
    end

    # One relative selector: an (optionally explicit) leading combinator
    # relative to the `:has()` anchor, then a complex selector. `combinator`
    # is `:descendant` (the implicit default, `:has(.x)`), `:child`
    # (`:has(> .x)`), `:next_sibling` (`:has(+ .x)`), or `:subsequent_sibling`
    # (`:has(~ .x)`).
    RelativeSelector = Data.define(:combinator, :complex) do
      include Node
      def to_s = Selectors::Serializer.serialize(self)
    end
  end
end
