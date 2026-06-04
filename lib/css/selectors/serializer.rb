module CSS
  module Selectors
    module Serializer
      extend self

      COMBINATOR_GLUE = {
        descendant:          ' ',
        child:               ' > ',
        next_sibling:        ' + ',
        subsequent_sibling:  ' ~ '
      }.freeze

      # Leading combinator of a `:has()` relative selector (descendant is
      # implicit, so it has no prefix).
      LEADING_COMBINATOR_GLUE = {
        descendant:          '',
        child:               '> ',
        next_sibling:        '+ ',
        subsequent_sibling:  '~ '
      }.freeze

      ATTR_OPS = {
        exact:     '=',
        includes:  '~=',
        dash:      '|=',
        prefix:    '^=',
        suffix:    '$=',
        substring: '*='
      }.freeze

      def serialize(node)
        case node
        when SelectorList      then node.selectors.map { serialize(_1) }.join(', ')
        when ComplexSelector   then serialize_complex(node)
        when CompoundSelector  then node.components.map { serialize(_1) }.join
        when TypeSelector      then ns_prefix(node.namespace) + Escape.ident(node.name)
        when UniversalSelector then "#{ns_prefix(node.namespace)}*"
        when NestingSelector   then '&'
        when IdSelector        then "##{Escape.ident(node.name)}"
        when ClassSelector     then ".#{Escape.ident(node.name)}"
        when AttributeSelector then serialize_attribute(node)
        when PseudoClass          then serialize_pseudo(node, '')
        when PseudoElement        then serialize_pseudo(node, ':')
        when AnB                  then serialize_anb(node)
        when RelativeSelectorList then node.selectors.map { serialize_relative(_1) }.join(', ')
        when RelativeSelector     then serialize_relative(node)
        else
          raise ArgumentError, "cannot serialize selector node #{node.class}"
        end
      end

      private

      def serialize_relative(rel)
        LEADING_COMBINATOR_GLUE.fetch(rel.combinator) + serialize(rel.complex)
      end

      def serialize_complex(cs)
        out = +serialize(cs.compounds[0])

        cs.combinators.each_with_index {|combo, i|
          out << COMBINATOR_GLUE.fetch(combo) << serialize(cs.compounds[i + 1])
        }

        out
      end

      def ns_prefix(namespace)
        case namespace
        when '*' then '*|'
        when ''  then '|'
        else          ''
        end
      end

      def serialize_attribute(attr)
        out = +"[#{ns_prefix(attr.namespace)}#{Escape.ident(attr.name)}"

        if attr.matcher
          out << ATTR_OPS.fetch(attr.matcher) << Escape.string(attr.value.to_s)
          out << " #{attr.case_flag}" if attr.case_flag
        end

        out << ']'
      end

      def serialize_pseudo(node, extra_colon)
        head = ":#{extra_colon}#{Escape.ident(node.name)}"

        return head if node.argument.nil?

        "#{head}(#{serialize_argument(node.argument)})"
      end

      def serialize_argument(arg)
        case arg
        when SelectorList         then serialize(arg)
        when RelativeSelectorList then serialize(arg)
        when AnB                  then serialize_anb(arg)
        when Array                then CSS::Serializer.serialize(arg)
        else
          raise ArgumentError, "unknown pseudo argument #{arg.class}"
        end
      end

      def serialize_anb(anb)
        out = serialize_anb_value(anb)
        out += " of #{serialize(anb.of)}" if anb.of
        out
      end

      def serialize_anb_value(anb)
        return 'even' if anb.step == 2 && anb.offset.zero?
        return 'odd'  if anb.step == 2 && anb.offset == 1

        return anb.offset.to_s if anb.step.zero?

        step_str =
          case anb.step
          when 1  then 'n'
          when -1 then '-n'
          else        "#{anb.step}n"
          end

        return step_str if anb.offset.zero?

        sign = anb.offset.positive? ? '+' : '-'
        "#{step_str}#{sign}#{anb.offset.abs}"
      end
    end
  end
end
