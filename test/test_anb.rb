require_relative 'test_helper'

class TestAnB < Minitest::Test
  AnB = CSS::Selectors::AnB

  def assert_anb(step, offset, input)
    result = CSS.parse_anb(input)

    assert_equal step,   result.step,   "step mismatch for #{input.inspect}"
    assert_equal offset, result.offset, "offset mismatch for #{input.inspect}"
  end

  def test_keywords
    assert_anb 2, 0, 'even'
    assert_anb 2, 1, 'odd'
    assert_anb 2, 0, 'EVEN'
    assert_anb 2, 1, 'ODD'
  end

  def test_pure_integer
    assert_anb 0,  5, '5'
    assert_anb 0, -3, '-3'
    assert_anb 0,  0, '0'
  end

  def test_n_alone
    assert_anb 1, 0, 'n'
    assert_anb 1, 0, '+n'
    assert_anb(-1, 0, '-n')
  end

  def test_an_form
    assert_anb 2,  0, '2n'
    assert_anb(-3, 0, '-3n')
  end

  def test_anplusb_form
    assert_anb 2,  1, '2n+1'
    assert_anb 2, -1, '2n-1'
    assert_anb 1,  3, 'n+3'
    assert_anb 1, -3, 'n-3'
  end

  def test_signed_anplusb_with_whitespace
    assert_anb 2,  1, '2n + 1'
    assert_anb 2, -1, '2n - 1'
    assert_anb 1,  3, 'n + 3'
  end

  def test_negative_step_with_offset
    assert_anb(-3, -2, '-3n-2')
    assert_anb(-1, -3, '-n-3')
    assert_anb(-3,  2, '-3n+2')
  end

  def test_plus_n_with_offset
    assert_anb 1, 2, '+n+2'
    assert_anb 1, -2, '+n-2'
  end

  # Errors --------------------------------------------------------------

  def test_empty_raises
    assert_raises(CSS::ParseError) { CSS.parse_anb('') }
  end

  def test_invalid_ident_raises
    assert_raises(CSS::ParseError) { CSS.parse_anb('xy') }
  end

  def test_dangling_plus_raises
    assert_raises(CSS::ParseError) { CSS.parse_anb('+') }
  end

  def test_trailing_garbage_raises
    assert_raises(CSS::ParseError) { CSS.parse_anb('2n+1 garbage') }
  end
end
