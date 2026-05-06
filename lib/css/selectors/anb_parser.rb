module CSS
  module Selectors
    # Parser for the An+B microsyntax used by `:nth-child(...)` and friends.
    # https://drafts.csswg.org/css-syntax/#anb-microsyntax
    module AnBParser
      EOF_TOKEN          = Token.new(:eof).freeze
      TRAILING_DASH_INT  = /\A-(\d+)\z/.freeze
      N_TRAILING_INT     = /\An(-\d+)?\z/i.freeze
      DASH_N_TRAILING    = /\A-n(-\d+)?\z/i.freeze

      module_function

      def parse(input)
        tokens = input.is_a?(String) ? Tokenizer.new(input).tokenize : input.to_a
        Impl.new(tokens).parse
      end

      class Impl
        def initialize(tokens)
          @tokens = tokens
          @pos    = 0
        end

        def parse
          skip_whitespace

          result = parse_value

          skip_whitespace

          unless peek.type == :eof
            raise ParseError, "trailing tokens in AnB: #{peek.type}"
          end

          result
        end

        private

        def peek(offset = 0)
          @tokens[@pos + offset] || EOF_TOKEN
        end

        def consume
          tok = @tokens[@pos] || EOF_TOKEN
          @pos += 1
          tok
        end

        def skip_whitespace
          consume while peek.type == :whitespace
        end

        def parse_value
          t = peek

          case t.type
          when :ident     then parse_ident_form(t)
          when :number    then parse_pure_number(t)
          when :dimension then parse_dimension_form(t)
          when :delim     then parse_signed_form(t)
          else
            raise ParseError, "expected An+B, got #{t.type}"
          end
        end

        def parse_ident_form(t)
          consume

          case t.value.downcase
          when 'even'
            AnB.new(step: 2, offset: 0)
          when 'odd'
            AnB.new(step: 2, offset: 1)
          when 'n'
            parse_offset(step: 1)
          when '-n'
            parse_offset(step: -1)
          when N_TRAILING_INT
            AnB.new(step: 1, offset: -extract_dash_int(t.value, prefix: 'n'))
          when DASH_N_TRAILING
            AnB.new(step: -1, offset: -extract_dash_int(t.value, prefix: '-n'))
          else
            raise ParseError, "invalid AnB identifier: #{t.value}"
          end
        end

        def parse_pure_number(t)
          consume

          raise ParseError, 'AnB integer must be an integer' unless t.flag == :integer

          AnB.new(step: 0, offset: t.value)
        end

        def parse_dimension_form(t)
          consume

          raise ParseError, 'AnB step coefficient must be an integer' unless t.flag == :integer

          unit = t.unit.downcase

          if unit == 'n'
            parse_offset(step: t.value)
          elsif unit.start_with?('n') && (m = TRAILING_DASH_INT.match(unit[1..]))
            AnB.new(step: t.value, offset: -m[1].to_i)
          else
            raise ParseError, "invalid AnB dimension unit: #{unit}"
          end
        end

        # `+n`, `+n+1`, `+n-1`, `+n-3` (where `+n-3` lexes as delim '+' then
        # ident "n-3"): consume the leading `+` and re-enter the ident path.
        def parse_signed_form(t)
          raise ParseError, "unexpected delim #{t.value}" unless t.value == '+'

          consume

          ident = peek

          unless ident.type == :ident
            raise ParseError, "expected ident after '+', got #{ident.type}"
          end

          consume

          case ident.value.downcase
          when 'n'
            parse_offset(step: 1)
          when N_TRAILING_INT
            AnB.new(step: 1, offset: -extract_dash_int(ident.value, prefix: 'n'))
          else
            raise ParseError, "invalid AnB after '+': #{ident.value}"
          end
        end

        def parse_offset(step:)
          skip_whitespace

          t = peek

          case t.type
          when :eof
            AnB.new(step:, offset: 0)
          when :number
            consume

            raise ParseError, 'AnB offset must be an integer' unless t.flag == :integer

            AnB.new(step:, offset: t.value)
          when :delim
            unless t.value == '+' || t.value == '-'
              raise ParseError, "expected +/- in AnB offset, got delim #{t.value}"
            end

            sign = t.value
            consume

            skip_whitespace

            n = peek

            unless n.type == :number && n.flag == :integer
              raise ParseError, "expected integer after #{sign}"
            end

            consume

            AnB.new(step:, offset: sign == '-' ? -n.value.abs : n.value.abs)
          else
            AnB.new(step:, offset: 0)
          end
        end

        def extract_dash_int(s, prefix:)
          rest = s.sub(/\A#{prefix}/i, '')
          return 0 if rest.empty?

          m = TRAILING_DASH_INT.match(rest)

          raise ParseError, "invalid AnB suffix: #{s}" unless m

          m[1].to_i
        end
      end
    end
  end
end
