require_relative 'test_helper'

class TestPosition < Minitest::Test
  def positions(input)
    CSS.tokenize(input).map(&:position)
  end

  def test_first_token_starts_at_1_1
    pos = CSS.tokenize('foo').first.position

    assert_equal 1, pos.line
    assert_equal 1, pos.column
    assert_equal 0, pos.offset
    assert_equal 3, pos.end_offset
  end

  def test_position_after_newline
    src = "a\nb"
    a, _, b = CSS.tokenize(src)

    assert_equal [1, 1], [a.position.line, a.position.column]
    assert_equal [2, 1], [b.position.line, b.position.column]
  end

  def test_position_with_indented_block
    src = "a {\n  color: red;\n}"
    color = CSS.tokenize(src).find { it.type == :ident && it.value == 'color' }

    assert_equal 2, color.position.line
    assert_equal 3, color.position.column
  end

  def test_offset_is_index_into_preprocessed_input
    src = "foo bar"
    bar = CSS.tokenize(src).find { it.value == 'bar' }

    assert_equal 4, bar.position.offset
    assert_equal 7, bar.position.end_offset
  end

  def test_position_through_comments
    src = "/* leading */ a"
    a = CSS.tokenize(src).find { it.type == :ident }

    assert_equal 1, a.position.line
    assert_equal 15, a.position.column
  end

  def test_token_equality_ignores_position
    a = CSS.tokenize('foo').first
    b = CSS::Token.new(:ident, 'foo')

    refute_nil a.position

    assert_equal a, b
  end

  def test_parse_error_carries_position
    err = assert_raises(CSS::ParseError) { CSS.parse_rule('a {} b') }

    refute_nil err.position
    assert_equal 1, err.position.line
    assert_match(/^1:\d+:/, err.message)
  end

  def test_parse_error_at_eof_has_no_position
    err = assert_raises(CSS::ParseError) { CSS.parse_rule('') }

    assert_nil err.position
    refute_match(/^\d+:\d+:/, err.message)
  end
end
