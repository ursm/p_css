module CSS
  module MediaQueries
    # Marker module for media-query AST nodes; lets the main serializer
    # dispatch into MediaQueries::Serializer when it ever exists.
    module Node; end

    MediaQueryList = Data.define(:queries) do
      include Node
    end

    # `modifier` is `nil`, `:not`, or `:only`.
    # `type` is `nil` or a downcased string ('screen', 'print', 'all', ...).
    # `condition` is `nil` or a media-condition node.
    MediaQuery = Data.define(:modifier, :type, :condition) do
      include Node
    end

    MediaNot = Data.define(:operand)        { include Node }
    MediaAnd = Data.define(:operands)       { include Node }
    MediaOr  = Data.define(:operands)       { include Node }

    # `op` is `nil` (boolean form, e.g. `(color)`), `:eq` (plain form,
    # `(min-width: 600px)`, or range `=`), `:lt`, `:le`, `:gt`, or `:ge`.
    # `value` is `nil` (boolean), a Token, or a Ratio.
    MediaFeature = Data.define(:name, :op, :value) do
      include Node
    end

    # Catch-all for `(...)` content the parser couldn't recognize as a
    # feature or condition. Preserved so downstream tools can still see it.
    GeneralEnclosed = Data.define(:tokens) do
      include Node
    end

    # Numeric ratio used in `aspect-ratio` / `device-aspect-ratio` features.
    Ratio = Data.define(:numerator, :denominator) do
      include Node
      def to_f = numerator.to_f / denominator
    end
  end
end
