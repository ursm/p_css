require_relative 'test_helper'

class TestSerializer < Minitest::Test
  def serialize(node)
    CSS.serialize(node)
  end

  def round_trip_stable?(src)
    out1 = serialize(CSS.parse_stylesheet(src))
    out2 = serialize(CSS.parse_stylesheet(out1))
    out1 == out2
  end

  # Token round-tripping ------------------------------------------------

  def assert_token_round_trip(token)
    out      = serialize(token)
    reparsed = CSS.tokenize(out).first

    assert_equal token, reparsed, "round-trip failed for #{token.inspect} (-> #{out.inspect})"
  end

  def test_ident_with_leading_digit
    assert_token_round_trip CSS::Token.new(:ident, '1abc')
  end

  def test_ident_with_hyphen_digit
    assert_token_round_trip CSS::Token.new(:ident, '-1abc')
  end

  def test_lone_hyphen_ident
    assert_token_round_trip CSS::Token.new(:ident, '-')
  end

  def test_ident_with_space
    assert_token_round_trip CSS::Token.new(:ident, 'a b')
  end

  def test_string_with_quotes_and_backslash
    assert_token_round_trip CSS::Token.new(:string, %q(He said "hi"))
  end

  def test_string_with_control_char
    assert_token_round_trip CSS::Token.new(:string, "tab\there")
  end

  def test_hash_id_flag_round_trip
    assert_token_round_trip CSS::Token.new(:hash, 'abc', flag: :id)
  end

  def test_hash_unrestricted_flag_round_trip
    assert_token_round_trip CSS::Token.new(:hash, '1ab', flag: :unrestricted)
  end

  def test_dimension_with_e_unit
    assert_token_round_trip CSS::Token.new(:dimension, 12, flag: :integer, unit: 'e3')
  end

  def test_dimension_normal_unit
    assert_token_round_trip CSS::Token.new(:dimension, 1.5, flag: :number, unit: 'px')
  end

  def test_percentage
    # Per Syntax 4, <percentage-token> has no type flag.
    assert_token_round_trip CSS::Token.new(:percentage, 50)
  end

  def test_number_integer_flag
    assert_token_round_trip CSS::Token.new(:number, 42, flag: :integer)
  end

  def test_number_number_flag_with_int_value
    # An integer-valued :number token must serialize so it re-parses with :number flag.
    out      = serialize(CSS::Token.new(:number, 1, flag: :number))
    reparsed = CSS.tokenize(out).first

    assert_equal :number, reparsed.flag
  end

  # Stylesheet round-trip ------------------------------------------------

  def test_round_trip_basic
    assert round_trip_stable?(<<~CSS)
      .foo, .bar {
        color: #abc;
        background: rgb(1, 2, 3);
        margin: 1em 2.5%;
      }
    CSS
  end

  def test_round_trip_nesting
    assert round_trip_stable?(<<~CSS)
      .card {
        padding: 1em;
        & .title { font-weight: 700 !important; }
        a:hover { color: red; }
        @media (min-width: 600px) { padding: 2em; }
      }
    CSS
  end

  def test_round_trip_at_rule_no_block
    assert round_trip_stable?('@charset "UTF-8";')
  end

  def test_serialize_declaration_node
    decl = CSS.parse_declaration('color: red !important')

    assert_equal 'color: red !important;', serialize(decl)
  end

  def test_serialize_block_contents
    block = CSS.parse_block_contents('color: red; background: blue;')

    assert_equal "color: red;\nbackground: blue;",
                 block.items.map { CSS.serialize(_1) }.join("\n")
  end

  def test_serialize_array_of_component_values
    values = CSS.parse_component_values('1px solid red')

    assert_equal '1px solid red', serialize(values)
  end

  # Number formatting ---------------------------------------------------

  def test_serialize_number_avoids_e_notation_small
    out = serialize(CSS::Token.new(:number, 0.00001, flag: :number))

    refute_match(/e/i, out)
  end

  def test_serialize_number_avoids_e_notation_large
    out = serialize(CSS::Token.new(:number, 1.0e20, flag: :number))

    refute_match(/e/i, out)
  end
end
