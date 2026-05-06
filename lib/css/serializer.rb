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

    # Serialize any AST node, token, or array of component values to a CSS
    # string.
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

      if rule.block
        "#{head} #{serialize_block(rule.block)}"
      else
        "#{head};"
      end
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
      value     = serialize(decl.value)

      "#{serialize_ident(decl.name)}: #{value}#{important};"
    end

    def serialize_function(fn)
      "#{serialize_ident(fn.name)}(#{serialize(fn.value)})"
    end

    SIMPLE_BLOCK_CLOSE = {'(' => ')', '[' => ']', '{' => '}'}.freeze

    def serialize_simple_block(block)
      "#{block.open}#{serialize(block.value)}#{SIMPLE_BLOCK_CLOSE.fetch(block.open)}"
    end

    # §9.3 Serialization of tokens.
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
      if t.flag == :id
        "##{serialize_ident(t.value)}"
      else
        "##{serialize_name(t.value)}"
      end
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

    # §9.3.6 Serialize a number. We avoid E-notation entirely.
    def serialize_number(value, flag)
      case
      when value.is_a?(Integer) && flag != :number
        value.to_s
      when value.is_a?(Integer)
        "#{value}.0"
      when value.finite?
        format_finite_float(value)
      else
        # NaN/Infinity can't be represented in CSS; fall back to "0".
        '0'
      end
    end

    def format_finite_float(f)
      # Ruby's Float#to_s uses E-notation for very small / very large values.
      # Build a decimal form when needed.
      s = f.to_s

      return s unless s.match?(/[eE]/)

      sign = f.negative? ? '-' : ''
      mantissa, exp = s.sub(/\A-/, '').split(/[eE]/)
      exp = exp.to_i
      whole, frac = mantissa.split('.')
      frac ||= ''

      digits  = whole + frac
      decimal = whole.length + exp

      if decimal <= 0
        body = '0.' + ('0' * -decimal) + digits.sub(/0+\z/, '')
      elsif decimal >= digits.length
        body = digits + ('0' * (decimal - digits.length)) + '.0'
      else
        body = digits[0, decimal] + '.' + digits[decimal..]
      end

      body = body.sub(/(\.\d*?)0+\z/, '\1').sub(/\.\z/, '.0')
      "#{sign}#{body}"
    end

    # §9.3.1 Serialize an identifier.
    def serialize_ident(ident)
      buf = +''

      ident.each_char.with_index {|c, i|
        cp = c.ord

        if cp.zero?
          buf << "�"
        elsif (0x01..0x1F).cover?(cp) || cp == 0x7F
          buf << format('\\%x ', cp)
        elsif i.zero? && c == '-' && ident.length == 1
          buf << '\\-'
        elsif (i.zero? && digit?(c)) ||
              (i == 1 && digit?(c) && ident.start_with?('-'))
          buf << format('\\%x ', cp)
        elsif cp >= 0x80 || ident_safe?(c)
          buf << c
        else
          buf << "\\#{c}"
        end
      }

      buf
    end

    # §9.3 "Serialize a name" — like ident but allows leading digits/hyphens
    # because hash-token (unrestricted) and similar contexts don't require
    # ident-start at position 0.
    def serialize_name(name)
      buf = +''

      name.each_char {|c|
        cp = c.ord

        if cp.zero?
          buf << "�"
        elsif (0x01..0x1F).cover?(cp) || cp == 0x7F
          buf << format('\\%x ', cp)
        elsif cp >= 0x80 || ident_safe?(c)
          buf << c
        else
          buf << "\\#{c}"
        end
      }

      buf
    end

    # §9.3.2 Serialize a string. Always uses double quotes.
    def serialize_string(s)
      buf = +'"'

      s.each_char {|c|
        cp = c.ord

        if cp.zero?
          buf << "�"
        elsif (0x01..0x1F).cover?(cp) || cp == 0x7F
          buf << format('\\%x ', cp)
        elsif c == '"' || c == '\\'
          buf << "\\#{c}"
        else
          buf << c
        end
      }

      buf << '"'
      buf
    end

    def digit?(c)
      c.match?(/\A\d\z/)
    end

    def ident_safe?(c)
      c.match?(/\A[A-Za-z0-9_\-]\z/)
    end

    def indent(str)
      str.lines.map { "#{INDENT}#{it}" }.join.then {
        it.end_with?("\n") ? it.chomp : it
      }
    end
  end
end
