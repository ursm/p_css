require_relative 'test_helper'

class TestMediaQueries < Minitest::Test
  M = CSS::MediaQueries

  # Parser ----------------------------------------------------------

  def parse(s) = CSS.parse_media_query_list(s)

  def test_type_only
    q = parse('screen').queries.first

    assert_equal 'screen', q.type
    assert_nil   q.modifier
    assert_nil   q.condition
  end

  def test_modifier_not
    q = parse('not screen').queries.first

    assert_equal :not,    q.modifier
    assert_equal 'screen', q.type
  end

  def test_modifier_only
    assert_equal :only, parse('only screen and (min-width: 600px)').queries.first.modifier
  end

  def test_feature_plain
    q = parse('(min-width: 600px)').queries.first

    cond = q.condition

    assert_kind_of M::MediaFeature, cond
    assert_equal 'min-width', cond.name
    assert_equal :eq,         cond.op
  end

  def test_feature_boolean
    q = parse('(color)').queries.first

    assert_kind_of M::MediaFeature, q.condition
    assert_nil q.condition.op
  end

  def test_range_simple
    q = parse('(width >= 600px)').queries.first

    assert_equal :ge, q.condition.op
  end

  def test_range_bounded_decomposes_to_and
    q = parse('(600px <= width < 1200px)').queries.first

    assert_kind_of M::MediaAnd, q.condition
    assert_equal 2, q.condition.operands.size
    assert_equal :ge, q.condition.operands[0].op
    assert_equal :lt, q.condition.operands[1].op
  end

  def test_and_chain
    cond = parse('(min-width: 600px) and (max-width: 1200px) and (orientation: landscape)').queries.first.condition

    assert_kind_of M::MediaAnd, cond
    assert_equal 3, cond.operands.size
  end

  def test_or_chain
    cond = parse('(min-width: 600px) or (orientation: portrait)').queries.first.condition

    assert_kind_of M::MediaOr, cond
  end

  def test_comma_separated_list
    assert_equal 2, parse('screen, print').queries.size
  end

  def test_aspect_ratio
    q = parse('(aspect-ratio: 16/9)').queries.first

    assert_kind_of M::Ratio, q.condition.value
    assert_equal 16, q.condition.value.numerator
    assert_equal 9,  q.condition.value.denominator
  end

  # Evaluator -------------------------------------------------------

  def matches?(query, **overrides)
    ctx = M::Context.default(**overrides)
    CSS.media_matches?(query, ctx)
  end

  def test_screen_matches_screen
    assert matches?('screen')
    refute matches?('print')
  end

  def test_min_width
    assert matches?('(min-width: 600px)', 'width' => 800)
    refute matches?('(min-width: 600px)', 'width' => 400)
  end

  def test_max_width
    assert matches?('(max-width: 600px)', 'width' => 400)
    refute matches?('(max-width: 600px)', 'width' => 800)
  end

  def test_combined_and
    assert matches?('screen and (min-width: 600px)', 'width' => 800)
    refute matches?('screen and (min-width: 600px)', 'width' => 400)
  end

  def test_combined_or
    assert matches?('(min-width: 1500px) or (max-width: 800px)', 'width' => 600)
    refute matches?('(min-width: 1500px) or (max-width: 800px)', 'width' => 1200)
  end

  def test_not_modifier
    refute matches?('not screen')
    assert matches?('not print')
  end

  def test_orientation_default_landscape
    assert matches?('(orientation: landscape)')
    refute matches?('(orientation: portrait)')
  end

  def test_prefers_color_scheme
    assert matches?('(prefers-color-scheme: dark)', 'prefers-color-scheme' => 'dark')
    refute matches?('(prefers-color-scheme: dark)', 'prefers-color-scheme' => 'light')
  end

  def test_em_length_converts_to_px
    # 50em == 800px at 16px base
    assert matches?('(min-width: 50em)', 'width' => 1000)
    refute matches?('(min-width: 50em)', 'width' => 600)
  end

  def test_pt_unit
    # 12pt == 16px
    assert matches?('(min-width: 12pt)', 'width' => 20)
  end

  def test_resolution_dppx
    assert matches?('(min-resolution: 1dppx)', 'resolution' => 1.0)
    refute matches?('(min-resolution: 2dppx)', 'resolution' => 1.0)
  end

  def test_range_form
    assert matches?('(width >= 600px)', 'width' => 800)
    refute matches?('(width > 800px)',  'width' => 800)
  end

  def test_bounded_range
    assert matches?('(600px <= width <= 1200px)', 'width' => 800)
    refute matches?('(600px <= width <= 1200px)', 'width' => 1500)
  end

  def test_general_enclosed_does_not_match
    # Unknown function-style media query falls through as general-enclosed.
    refute matches?('(unknown-function-feature)')
  end
end
