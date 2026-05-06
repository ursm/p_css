require_relative 'css/version'
require_relative 'css/code_points'
require_relative 'css/token'
require_relative 'css/tokenizer'
require_relative 'css/nodes'
require_relative 'css/parser'
require_relative 'css/serializer'
require_relative 'css/urange'

module CSS
  # Bracket information for the three "simple block" pairs. Indexed both by
  # opening token type (for the parser) and by opening character (for the
  # serializer).
  BRACKET_OPEN_CHAR  = {lbrace: '{', lbracket: '[', lparen: '('}.freeze
  BRACKET_CLOSE_TYPE = {lbrace: :rbrace, lbracket: :rbracket, lparen: :rparen}.freeze
  BRACKET_PAIRS      = {'{' => '}', '[' => ']', '(' => ')'}.freeze

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

    def serialize(node) = Serializer.serialize(node)

    alias parse parse_stylesheet
  end
end
