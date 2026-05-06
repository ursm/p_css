module CSS
  module Nodes
    # A complete stylesheet: a list of top-level rules.
    Stylesheet = Data.define(:rules)

    # An at-rule, e.g. `@media (min-width: 600px) { ... }` or `@charset "UTF-8";`.
    # `prelude` is an array of component values, `block` is a Block or nil.
    AtRule = Data.define(:name, :prelude, :block)

    # A qualified rule, i.e. a style rule. `prelude` is the selector list as
    # raw component values, `block` is the body.
    QualifiedRule = Data.define(:prelude, :block)

    # The body of a qualified rule or at-rule. Contains a list of declarations,
    # nested qualified rules, and nested at-rules in source order.
    Block = Data.define(:items)

    # `name: value [!important]`.
    Declaration = Data.define(:name, :value, :important)

    # A function reference like `rgb(255, 0, 0)`. `value` is an array of
    # component values.
    Function = Data.define(:name, :value)

    # A `( ... )`, `[ ... ]`, or `{ ... }` block as a component value.
    # `open` is one of `(`, `[`, `{`. `value` is an array of component values.
    SimpleBlock = Data.define(:open, :value) do
      def braced?      = open == '{'
      def bracketed?   = open == '['
      def parenthesized? = open == '('
    end

    # An inclusive code-point range, e.g. `U+0-7F`. Result of CSS.parse_urange.
    UnicodeRange = Data.define(:first, :last) do
      def cover?(cp) = (first..last).cover?(cp)

      def to_s
        first == last ? format('U+%X', first) : format('U+%X-%X', first, last)
      end
    end
  end
end
