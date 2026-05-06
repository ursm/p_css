module CSS
  module MediaQueries
    # Evaluates a MediaQueryList against a Context, returning true if at
    # least one media-query in the list matches.
    module Evaluator
      extend self

      # Length conversion to CSS px assumes 1em = 1rem = 16px. Per Media
      # Queries Level 4 §1.3 this is the conventional fallback when the
      # font-size of the root is unknown.
      EM_PX = 16.0

      LENGTH_UNITS_PX = {
        'px'  => 1.0,
        'em'  => EM_PX,
        'rem' => EM_PX,
        'ex'  => EM_PX * 0.5,
        'ch'  => EM_PX * 0.5,
        'pt'  => 96.0 / 72,
        'pc'  => 16.0,
        'in'  => 96.0,
        'cm'  => 96.0 / 2.54,
        'mm'  => 96.0 / 25.4,
        'q'   => 96.0 / 25.4 / 4
      }.freeze

      RESOLUTION_UNITS_DPPX = {
        'dppx' => 1.0,
        'x'    => 1.0,
        'dpi'  => 1.0 / 96,
        'dpcm' => 2.54 / 96
      }.freeze

      RESOLUTION_FEATURES = %w[resolution].freeze

      INVERSE_OP = {lt: :gt, le: :ge, gt: :lt, ge: :le, eq: :eq}.freeze

      PREFIX_OP = {min: :ge, max: :le}.freeze

      def evaluate(query_list, context)
        query_list.queries.any? { evaluate_query(it, context) }
      end

      private

      def evaluate_query(query, context)
        result = evaluate_query_main(query, context)
        query.modifier == :not ? !result : result
      end

      def evaluate_query_main(query, context)
        if query.type
          return false unless type_matches?(query.type, context.media_type)
        end

        return true if query.condition.nil?

        evaluate_condition(query.condition, context)
      end

      def type_matches?(type, ctx_type)
        type == 'all' || type == ctx_type.to_s
      end

      def evaluate_condition(node, context)
        case node
        when MediaNot       then !evaluate_condition(node.operand, context)
        when MediaAnd       then node.operands.all? { evaluate_condition(it, context) }
        when MediaOr        then node.operands.any? { evaluate_condition(it, context) }
        when MediaFeature   then evaluate_feature(node, context)
        when GeneralEnclosed then false
        else                      false
        end
      end

      def evaluate_feature(feature, context)
        ctx_name, prefix = strip_prefix(feature.name)
        ctx_value = context[ctx_name]

        return evaluate_boolean(ctx_value) if feature.op.nil?

        compare(prefix, feature.op, ctx_value, feature.value, ctx_name)
      end

      def evaluate_boolean(ctx_value)
        return false if ctx_value.nil?
        return false if ctx_value == 0 || ctx_value == false || ctx_value == '' || ctx_value == 'none'

        true
      end

      def strip_prefix(name)
        case name
        when /\Amin-(.+)/ then [$1, :min]
        when /\Amax-(.+)/ then [$1, :max]
        else                   [name, nil]
        end
      end

      def compare(prefix, op, ctx_value, feature_value, ctx_name)
        op = PREFIX_OP[prefix] || op

        return string_op_apply(op, ctx_value.to_s, feature_value.value.to_s) if ident_compare?(feature_value)

        a = numeric_for(ctx_name, ctx_value)
        b = numeric_for(ctx_name, feature_value)

        return false if a.nil? || b.nil?

        numeric_op_apply(op, a, b)
      end

      def ident_compare?(feature_value)
        feature_value.is_a?(Token) && feature_value.type == :ident
      end

      def string_op_apply(op, a, b)
        op == :eq && a.casecmp?(b)
      end

      def numeric_op_apply(op, a, b)
        case op
        when :eq then a == b
        when :lt then a < b
        when :le then a <= b
        when :gt then a > b
        when :ge then a >= b
        end
      end

      # Converts both context value and feature value to a comparable
      # numeric in the canonical unit for the named feature.
      def numeric_for(ctx_name, value)
        case value
        when Numeric then value.to_f
        when Ratio   then value.to_f
        when Token
          case value.type
          when :number     then value.value.to_f
          when :percentage then value.value.to_f / 100
          when :dimension  then dimension_to_canonical(value, ctx_name)
          else                  nil
          end
        else nil
        end
      end

      def dimension_to_canonical(token, ctx_name)
        unit  = token.unit.downcase
        table = RESOLUTION_FEATURES.include?(ctx_name) ? RESOLUTION_UNITS_DPPX : LENGTH_UNITS_PX

        factor = table[unit]
        factor && token.value.to_f * factor
      end
    end
  end
end
