require_relative 'test_helper'

class TestUrange < Minitest::Test
  include CSS::Nodes

  def test_single_codepoint
    r = CSS.parse_urange('U+26')

    assert_equal 0x26, r.first
    assert_equal 0x26, r.last
  end

  def test_zero
    r = CSS.parse_urange('U+0')

    assert_equal 0, r.first
    assert_equal 0, r.last
  end

  def test_explicit_range
    r = CSS.parse_urange('U+0-7F')

    assert_equal 0x00, r.first
    assert_equal 0x7F, r.last
  end

  def test_wildcard_expands_to_range
    r = CSS.parse_urange('U+10??')

    assert_equal 0x1000, r.first
    assert_equal 0x10FF, r.last
  end

  def test_all_wildcards
    r = CSS.parse_urange('U+????')

    assert_equal 0x0000, r.first
    assert_equal 0xFFFF, r.last
  end

  def test_lowercase_u_accepted
    assert_equal 0xABCD, CSS.parse_urange('u+abcd').first
  end

  def test_max_codepoint
    r = CSS.parse_urange('U+10FFFF')

    assert_equal 0x10FFFF, r.last
  end

  def test_whitespace_around_input_tolerated
    r = CSS.parse_urange("  U+26  \n")

    assert_equal 0x26, r.first
  end

  def test_cover_predicate
    r = CSS.parse_urange('U+0-7F')

    assert r.cover?(0x40)
    refute r.cover?(0x80)
  end

  def test_to_s_for_single_codepoint
    assert_equal 'U+26', CSS.parse_urange('U+26').to_s
  end

  def test_to_s_for_range
    assert_equal 'U+0-7F', CSS.parse_urange('U+0-7F').to_s
  end

  # Invalid input -----------------------------------------------------

  def test_missing_u_prefix_raises
    assert_raises(CSS::ParseError) { CSS.parse_urange('+26') }
    assert_raises(CSS::ParseError) { CSS.parse_urange('X+0') }
  end

  def test_missing_codepoints_raises
    assert_raises(CSS::ParseError) { CSS.parse_urange('U+') }
  end

  def test_too_many_hex_digits_raises
    assert_raises(CSS::ParseError) { CSS.parse_urange('U+1234567') }
  end

  def test_codepoint_out_of_range_raises
    err = assert_raises(CSS::ParseError) { CSS.parse_urange('U+FFFFFF') }

    assert_match(/out of range/, err.message)
  end

  def test_inverted_range_raises
    err = assert_raises(CSS::ParseError) { CSS.parse_urange('U+10-5') }

    assert_match(/start must be <= end/, err.message)
  end

  def test_wildcards_in_range_form_raises
    err = assert_raises(CSS::ParseError) { CSS.parse_urange('U+0?-FF') }

    assert_match(/wildcards/, err.message)
  end

  def test_wildcards_must_trail
    err = assert_raises(CSS::ParseError) { CSS.parse_urange('U+1?2') }

    assert_match(/trailing/, err.message)
  end
end
