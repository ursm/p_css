module CSS
  # Bracket information for the three "simple block" pairs. Indexed both by
  # opening token type (for the parser) and by opening character (for the
  # serializer).
  BRACKET_OPEN_CHAR  = {lbrace: '{', lbracket: '[', lparen: '('}.freeze
  BRACKET_CLOSE_TYPE = {lbrace: :rbrace, lbracket: :rbracket, lparen: :rparen}.freeze
  BRACKET_PAIRS      = {'{' => '}', '[' => ']', '(' => ')'}.freeze
end

require_relative 'css/version'
require_relative 'css/code_points'
require_relative 'css/escape'
require_relative 'css/token'
require_relative 'css/tokenizer'
require_relative 'css/nodes'
require_relative 'css/parser'
require_relative 'css/selectors'
require_relative 'css/media_queries'
require_relative 'css/serializer'
require_relative 'css/urange'
require_relative 'css/nesting'
require_relative 'css/cascade'

module CSS
  class ParseError < StandardError
    attr_reader :position

    def initialize(message, position: nil)
      super(position ? "#{position}: #{message}" : message)
      @position = position
    end
  end

  class << self
    def tokenize(input, **opts)                    = Tokenizer.new(input, **opts).tokenize
    def parse_stylesheet(input, **opts)            = Parser.parse_stylesheet(input, **opts)
    def parse_rule(input, **opts)                  = Parser.parse_rule(input, **opts)
    def parse_declaration(input, **opts)           = Parser.parse_declaration(input, **opts)
    def parse_block_contents(input, **opts)        = Parser.parse_block_contents(input, **opts)
    def parse_component_value(input, **opts)       = Parser.parse_component_value(input, **opts)
    def parse_component_values(input, **opts)      = Parser.parse_component_values(input, **opts)
    def parse_comma_separated_values(input, **opts) = Parser.parse_comma_separated_values(input, **opts)

    def parse_urange(input) = Urange.parse(input)

    def parse_selector_list(input) = Selectors::Parser.parse_selector_list(input)
    def parse_selector(input)      = Selectors::Parser.parse_selector(input)
    def parse_anb(input)           = Selectors::AnBParser.parse(input)

    def specificity(selector) = Selectors::SpecificityCalculator.calculate(selector)

    def matches?(element, selector) = Selectors::Matcher.matches?(element, selector)

    def parse_media_query_list(input) = MediaQueries::Parser.parse(input)

    def media_matches?(query_list, context)
      ql = query_list.is_a?(String) ? MediaQueries::Parser.parse(query_list) : query_list
      ctx = context.is_a?(MediaQueries::Context) ? context : MediaQueries::Context.default(**context.to_h)
      MediaQueries::Evaluator.evaluate(ql, ctx)
    end

    def cascade(stylesheet, context: MediaQueries::Context.default)
      Cascade.new(stylesheet, context:)
    end

    def desugar(stylesheet) = Nesting.desugar(stylesheet)

    def serialize(node) = Serializer.serialize(node)

    alias parse parse_stylesheet
  end
end
