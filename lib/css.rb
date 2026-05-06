require_relative 'css/version'
require_relative 'css/token'
require_relative 'css/tokenizer'
require_relative 'css/nodes'
require_relative 'css/parser'
require_relative 'css/serializer'

module CSS
  class ParseError < StandardError
    attr_reader :position

    def initialize(message, position: nil)
      super(position ? "#{position}: #{message}" : message)
      @position = position
    end
  end

  class << self
    def tokenize(input)                    = Tokenizer.new(input).tokenize
    def parse_stylesheet(input)            = Parser.parse_stylesheet(input)
    def parse_rule(input)                  = Parser.parse_rule(input)
    def parse_declaration(input)           = Parser.parse_declaration(input)
    def parse_block_contents(input)        = Parser.parse_block_contents(input)
    def parse_component_value(input)       = Parser.parse_component_value(input)
    def parse_component_values(input)      = Parser.parse_component_values(input)
    def parse_comma_separated_values(input) = Parser.parse_comma_separated_values(input)

    def serialize(node) = Serializer.serialize(node)

    alias parse parse_stylesheet
  end
end
