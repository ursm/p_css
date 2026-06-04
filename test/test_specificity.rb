require_relative 'test_helper'

class TestSpecificity < Minitest::Test
  S = CSS::Selectors

  def assert_spec(a, b, c, selector)
    actual = CSS.specificity(CSS.parse_selector_list(selector))

    assert_equal S::Specificity.new(a:, b:, c:), actual,
                 "specificity of #{selector.inspect}"
  end

  def test_universal
    assert_spec 0, 0, 0, '*'
  end

  def test_type
    assert_spec 0, 0, 1, 'div'
  end

  def test_class
    assert_spec 0, 1, 0, '.foo'
  end

  def test_id
    assert_spec 1, 0, 0, '#foo'
  end

  def test_compound
    assert_spec 0, 2, 1, 'div.foo.bar'
  end

  def test_attribute_counts_as_class
    assert_spec 0, 1, 0, '[href]'
  end

  def test_pseudo_class_counts_as_class
    assert_spec 0, 1, 1, 'a:hover'
  end

  def test_pseudo_element_counts_as_type
    assert_spec 0, 0, 2, 'div::before'
  end

  def test_descendant_sums_compounds
    assert_spec 2, 0, 0, '#a #b'
  end

  def test_combinators_dont_count
    assert_spec 0, 0, 2, 'a > b'
  end

  def test_is_uses_max_argument
    assert_spec 1, 0, 0, ':is(.foo, #bar)'
  end

  def test_where_is_zero
    assert_spec 0, 0, 0, ':where(#bar)'
  end

  def test_not_uses_max_argument
    assert_spec 0, 1, 0, ':not(.foo, [href])'
  end

  def test_has_uses_max_argument
    # `:has()` contributes the most specific complex selector in its argument
    # (like `:is`), so `#a` dominates `.b`. Plus the type selector `div`.
    assert_spec 1, 0, 1, 'div:has(#a, .b)'
  end

  def test_has_child_argument_specificity
    assert_spec 0, 0, 2, 'div:has(> p)'
  end

  def test_selector_list_takes_max
    assert_spec 1, 0, 0, '.a, #b'
  end

  def test_specificity_compares
    a = CSS.specificity(CSS.parse_selector_list('#x'))
    b = CSS.specificity(CSS.parse_selector_list('.x.y.z'))

    assert a > b
  end

  def test_specificity_sums
    s = S::Specificity.new(a: 1, b: 2, c: 3) + S::Specificity.new(a: 0, b: 1, c: 1)

    assert_equal S::Specificity.new(a: 1, b: 3, c: 4), s
  end

  def test_to_s
    assert_equal '1,2,3', S::Specificity.new(a: 1, b: 2, c: 3).to_s
  end
end
