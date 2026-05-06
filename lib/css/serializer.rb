module CSS
  # Serializer based on CSS Syntax Module Level 4 §9 Serialization.
  # https://drafts.csswg.org/css-syntax/#serialization
  #
  # The output is intended to round-trip: re-parsing it should yield an
  # equivalent AST. Idents, strings, hashes, and dimensions are escaped
  # following the spec rules.
  module Serializer
    extend self

    INDENT = '  '.freeze

    def serialize(node)
      case node
      when Nodes::Stylesheet    then serialize_stylesheet(node)
      when Nodes::AtRule        then serialize_at_rule(node)
      when Nodes::QualifiedRule then serialize_qualified_rule(node)
      when Nodes::Block         then serialize_block(node)
      when Nodes::Declaration   then serialize_declaration(node)
      when Nodes::Function      then serialize_function(node)
      when Nodes::SimpleBlock   then serialize_simple_block(node)
      when Token                then serialize_token(node)
      when Selectors::Node      then Selectors::Serializer.serialize(node)
      when Array                then node.map { serialize(it) }.join
      else
        raise ArgumentError, "cannot serialize #{node.class}"
      end
    end

    private

    def serialize_stylesheet(ss)
      ss.rules.map { serialize(it) }.join("\n")
    end

    def serialize_at_rule(rule)
      head = "@#{serialize_ident(rule.name)}"

      prelude_str = serialize(rule.prelude)
      head += " #{prelude_str}" unless prelude_str.empty?

      rule.block ? "#{head} #{serialize_block(rule.block)}" : "#{head};"
    end

    def serialize_qualified_rule(rule)
      "#{serialize(rule.prelude)} #{serialize_block(rule.block)}"
    end

    def serialize_block(block)
      return '{}' if block.items.empty?

      inner = block.items.map { serialize(it) }.join("\n")
      "{\n#{indent(inner)}\n}"
    end

    def serialize_declaration(decl)
      important = decl.important ? ' !important' : ''
      "#{serialize_ident(decl.name)}: #{serialize(decl.value)}#{important};"
    end

    def serialize_function(fn)
      "#{serialize_ident(fn.name)}(#{serialize(fn.value)})"
    end

    def serialize_simple_block(block)
      "#{block.open}#{serialize(block.value)}#{BRACKET_PAIRS.fetch(block.open)}"
    end

    # §9.3.
    def serialize_token(t)
      case t.type
      when :ident      then serialize_ident(t.value)
      when :function   then "#{serialize_ident(t.value)}("
      when :at_keyword then "@#{serialize_ident(t.value)}"
      when :hash       then serialize_hash(t)
      when :string     then serialize_string(t.value)
      when :url        then "url(#{serialize_string(t.value)})"
      when :bad_string, :bad_url then ''
      when :delim      then t.value
      when :number     then serialize_number(t.value, t.flag)
      when :percentage then "#{serialize_number(t.value, :integer)}%"
      when :dimension  then serialize_dimension(t)
      when :whitespace then ' '
      when :comment    then "/*#{t.value}*/"
      when :cdo        then '<!--'
      when :cdc        then '-->'
      when :colon      then ':'
      when :semicolon  then ';'
      when :comma      then ','
      when :lbracket   then '['
      when :rbracket   then ']'
      when :lparen     then '('
      when :rparen     then ')'
      when :lbrace     then '{'
      when :rbrace     then '}'
      when :eof        then ''
      end
    end

    def serialize_hash(t)
      t.flag == :id ? "##{serialize_ident(t.value)}" : "##{serialize_name(t.value)}"
    end

    def serialize_dimension(t)
      "#{serialize_number(t.value, t.flag)}#{serialize_dimension_unit(t.unit)}"
    end

    # If a unit starts with `e[+-]?<digit>`, the leading `e` would re-merge
    # into the number's exponent on re-tokenization. Escape it.
    def serialize_dimension_unit(unit)
      if unit.match?(/\A[eE](?:[+-]?\d)/)
        "\\#{format('%X', unit[0].ord)} #{unit[1..]}"
      else
        serialize_ident(unit)
      end
    end

    # §9.3.6. Avoids E-notation entirely.
    def serialize_number(value, flag)
      case
      when value.is_a?(Integer) && flag != :number
        value.to_s
      when value.is_a?(Integer)
        "#{value}.0"
      when value.finite?
        format_finite_float(value)
      else
        '0'
      end
    end

    def format_finite_float(f)
      s = f.to_s
      return s unless s.match?(/[eE]/)

      sign         = f.negative? ? '-' : ''
      mantissa, e  = s.sub(/\A-/, '').split(/[eE]/)
      e            = e.to_i
      whole, frac  = mantissa.split('.')
      frac       ||= ''

      digits  = whole + frac
      decimal = whole.length + e

      body =
        if decimal <= 0
          '0.' + ('0' * -decimal) + digits.sub(/0+\z/, '')
        elsif decimal >= digits.length
          digits + ('0' * (decimal - digits.length)) + '.0'
        else
          "#{digits[0, decimal]}.#{digits[decimal..]}"
        end

      "#{sign}#{body.sub(/(\.\d*?)0+\z/, '\1').sub(/\.\z/, '.0')}"
    end

    def serialize_ident(s)  = Escape.ident(s)
    def serialize_name(s)   = Escape.name(s)
    def serialize_string(s) = Escape.string(s)

    def indent(str)
      str.lines.map { "#{INDENT}#{it}" }.join.then {
        it.end_with?("\n") ? it.chomp : it
      }
    end
  end
end
