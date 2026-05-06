require_relative 'test_helper'
require 'nokogiri'

class TestCascade < Minitest::Test
  def doc(html)
    Nokogiri::HTML::DocumentFragment.parse(html)
  end

  def cascade(css, **opts)
    ctx = CSS::MediaQueries::Context.default(**opts)
    CSS.cascade(CSS.parse_stylesheet(css), context: ctx)
  end

  def value(decl)
    CSS.serialize(decl.value)
  end

  # Specificity ----------------------------------------------------

  def test_higher_specificity_wins
    el = doc('<p class="x">hi</p>').at_css('p')
    c  = cascade('p { color: red } .x { color: blue }')

    assert_equal 'blue', value(c.resolve(el)['color'])
  end

  def test_id_beats_class
    el = doc('<p id="foo" class="bar">hi</p>').at_css('p')
    c  = cascade('.bar { color: red } #foo { color: blue }')

    assert_equal 'blue', value(c.resolve(el)['color'])
  end

  # Source order ---------------------------------------------------

  def test_later_source_wins_when_equal_specificity
    el = doc('<p class="a b">hi</p>').at_css('p')
    c  = cascade('.a { color: red } .b { color: blue }')

    assert_equal 'blue', value(c.resolve(el)['color'])
  end

  # !important -----------------------------------------------------

  def test_important_beats_unimportant
    el = doc('<p id="foo" class="x">hi</p>').at_css('p')
    c  = cascade('#foo { color: red } .x { color: blue !important }')

    assert_equal 'blue', value(c.resolve(el)['color'])
  end

  # Inline ---------------------------------------------------------

  def test_inline_beats_author_normal
    el = doc('<p>hi</p>').at_css('p')
    c  = cascade('p { color: red }')

    winner = c.resolve(el, inline_style: 'color: blue')

    assert_equal 'blue', value(winner['color'])
  end

  def test_important_author_beats_normal_inline
    el = doc('<p>hi</p>').at_css('p')
    c  = cascade('p { color: red !important }')

    winner = c.resolve(el, inline_style: 'color: blue')

    assert_equal 'red', value(winner['color'])
  end

  def test_inline_picks_up_orphan_property
    el = doc('<p>hi</p>').at_css('p')
    c  = cascade('p { color: red }')

    winner = c.resolve(el, inline_style: 'font-weight: bold')

    assert_equal 'red',  value(winner['color'])
    assert_equal 'bold', value(winner['font-weight'])
  end

  # @media ---------------------------------------------------------

  def test_media_filters_by_context
    el  = doc('<p class="a">hi</p>').at_css('p')
    css = '.a { padding: 0 } @media (min-width: 1000px) { .a { padding: 2rem } }'

    wide   = cascade(css, 'width' => 1200).resolve(el)
    narrow = cascade(css, 'width' => 600).resolve(el)

    assert_equal '2rem', value(wide['padding'])
    assert_equal '0',    value(narrow['padding'])
  end

  def test_nested_media_within_media
    el  = doc('<p class="a">hi</p>').at_css('p')
    css = <<~CSS
      .a { padding: 0 }
      @media (min-width: 600px) {
        @media (orientation: landscape) {
          .a { padding: 1rem }
        }
      }
    CSS

    landscape = cascade(css, 'width' => 800, 'orientation' => 'landscape').resolve(el)
    portrait  = cascade(css, 'width' => 800, 'orientation' => 'portrait').resolve(el)

    assert_equal '1rem', value(landscape['padding'])
    assert_equal '0',    value(portrait['padding'])
  end

  # Selector list within rule --------------------------------------

  def test_selector_list_uses_max_matching_specificity
    el = doc('<p class="x">hi</p>').at_css('p')
    c  = cascade('p, #nope { color: red }')  # only `p` matches

    assert_equal 'red', value(c.resolve(el)['color'])
  end

  # Robustness -----------------------------------------------------

  def test_bad_selector_skips_rule_silently
    el = doc('<p>hi</p>').at_css('p')
    # The first rule's prelude is invalid as a selector list and gets
    # skipped without affecting later rules.
    c  = cascade('@@@ { color: blue } p { color: red }')

    assert_equal 'red', value(c.resolve(el)['color'])
  end

  def test_unknown_at_rule_is_skipped_or_passthrough
    el = doc('<p class="x">hi</p>').at_css('p')

    # @supports blocks are descended into.
    c = cascade('@supports (display: grid) { .x { color: red } }')

    assert_equal 'red', value(c.resolve(el)['color'])
  end
end
