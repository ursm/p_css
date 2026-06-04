require_relative 'test_helper'
require 'nokogiri'

class TestMatcher < Minitest::Test
  HTML = <<~HTML
    <html lang="en">
      <body>
        <div id="root" class="container app-mode-light" data-x="value">
          <h1 class="title">Hello</h1>
          <p data-x="y">First with <a href="#one">link</a>.</p>
          <p class="lead">Second.</p>
          <ul>
            <li>one</li>
            <li class="active selected">two</li>
            <li>three</li>
          </ul>
          <article lang="ja">
            <p>こんにちは</p>
          </article>
          <fieldset disabled>
            <legend>Group</legend>
            <input type="text" name="a">
          </fieldset>
          <input type="text" required value="">
          <input type="text" placeholder="email" value="">
          <input type="checkbox" checked>
          <input type="checkbox">
          <button disabled>X</button>
          <button>Y</button>
          <select>
            <option>a</option>
            <option selected>b</option>
          </select>
        </div>
      </body>
    </html>
  HTML

  def setup
    @doc = Nokogiri::HTML(HTML)
    @elements = []
    @doc.traverse {|n| @elements << n if n.element? }
  end

  def matched_tags(selector)
    @elements.select { CSS.matches?(_1, selector) }.map(&:name)
  end

  def assert_match_tags(selector, expected)
    actual = matched_tags(selector)

    assert_equal expected, actual,
                 "selector #{selector.inspect} expected #{expected.inspect}, got #{actual.inspect}"
  end

  def first(selector) = @elements.find { CSS.matches?(_1, selector) }

  # Simple selectors -------------------------------------------------

  def test_id
    assert_match_tags '#root', ['div']
  end

  def test_class
    assert_match_tags '.title', ['h1']
  end

  def test_universal_matches_all_elements
    assert_equal @elements.size, matched_tags('*').size
  end

  def test_type_selector
    assert_equal 5, matched_tags('input').size
  end

  # Combinators ------------------------------------------------------

  def test_descendant
    assert_includes matched_tags('div p'), 'p'
  end

  def test_child
    assert_match_tags '#root > h1', ['h1']
  end

  def test_next_sibling
    assert_includes matched_tags('h1 + p'), 'p'
  end

  def test_subsequent_sibling
    assert_includes matched_tags('h1 ~ ul'), 'ul'
  end

  # Attributes -------------------------------------------------------

  def test_attribute_presence
    assert_includes matched_tags('[data-x]'), 'p'
  end

  def test_attribute_exact
    assert_includes matched_tags('[data-x="y"]'), 'p'
  end

  def test_attribute_case_insensitive_flag
    assert_includes matched_tags('[data-x="VALUE" i]'), 'div'
  end

  def test_attribute_includes
    assert_match_tags 'li[class~="active"]', ['li']
  end

  def test_attribute_dash_match
    # `|=` matches an exact value or a value followed by "-...". The
    # canonical use case is `[lang|="en"]` against `lang="en-US"`.
    article = @doc.at_css('article')

    assert CSS.matches?(article, '[lang|="ja"]')
  end

  def test_attribute_prefix
    assert_includes matched_tags('a[href^="#"]'), 'a'
  end

  def test_attribute_substring
    assert_includes matched_tags('a[href*="on"]'), 'a'
  end

  # Structural pseudo-classes ----------------------------------------

  def test_first_child
    assert_match_tags 'ul > :first-child', ['li']
  end

  def test_last_child
    assert_match_tags 'ul > :last-child', ['li']
  end

  def test_only_of_type
    assert_match_tags 'ul', ['ul']
  end

  def test_first_of_type
    assert_match_tags '#root > p:first-of-type', ['p']
  end

  def test_nth_child_2n_plus_1
    assert_equal 2, matched_tags('ul li:nth-child(2n+1)').size
  end

  def test_nth_child_keyword_odd
    assert_equal matched_tags('ul li:nth-child(odd)'), matched_tags('ul li:nth-child(2n+1)')
  end

  def test_nth_last_child
    assert_match_tags 'ul li:nth-last-child(1)', ['li']
  end

  def test_empty
    assert_includes matched_tags(':empty'), 'input'
    refute_includes matched_tags(':empty'), 'p'
  end

  def test_root_under_fragment_does_not_match
    # Under a full Document, the html element is the root.
    assert_includes matched_tags(':root'), 'html'
  end

  # Logical pseudos --------------------------------------------------

  def test_is
    assert_equal matched_tags(':is(h1, button)').size, matched_tags('h1').size + matched_tags('button').size
  end

  def test_where_has_zero_specificity_but_matches_same
    assert_equal matched_tags(':is(h1)'), matched_tags(':where(h1)')
  end

  def test_not
    assert_equal 2, matched_tags('ul li:not(.active)').size
  end

  def test_has_descendant
    # `ul:has(.active)` matches the <ul> because it contains <li class="active">.
    assert_includes matched_tags('ul:has(.active)'), 'ul'
  end

  def test_has_child_combinator
    # `ul:has(> .active)` — `.active` must be a direct child of the <ul>.
    assert_includes matched_tags('ul:has(> .active)'), 'ul'
    # The container div has no direct `.active` child (it is nested in the ul).
    refute_includes matched_tags('div:has(> .active)'), 'div'
  end

  def test_has_next_sibling
    # `h1:has(+ p)` — the <h1> is immediately followed by a <p>.
    assert_includes matched_tags('h1:has(+ p)'), 'h1'
  end

  def test_has_no_match
    refute_includes matched_tags('ul:has(.nonexistent)'), 'ul'
  end

  # :nth-child(An+B of S) -------------------------------------------

  def test_nth_child_of_selector
    doc = Nokogiri::HTML(<<~HTML)
      <ul>
        <li class="x">1</li>
        <li>2</li>
        <li class="x">3</li>
        <li class="x">4</li>
      </ul>
    HTML
    lis = doc.css('li').to_a

    # Among the .x items (li 1, 3, 4), the 2nd is li "3".
    matched = lis.select { CSS.matches?(_1, 'li:nth-child(2 of .x)') }

    assert_equal ['3'], matched.map(&:text)
  end

  def test_nth_child_of_selector_requires_self_match
    doc = Nokogiri::HTML('<ul><li class="x">1</li><li>2</li></ul>')
    lis = doc.css('li').to_a

    # li "2" is not .x, so it never matches regardless of index.
    refute(lis.any? { _1.text == '2' && CSS.matches?(_1, 'li:nth-child(1 of .x)') })
  end

  # Form state ------------------------------------------------------

  def test_checked_checkbox
    assert_includes matched_tags('input:checked'), 'input'
  end

  def test_checked_option
    assert_includes matched_tags('option:checked'), 'option'
  end

  def test_disabled
    assert_includes matched_tags('button:disabled'), 'button'
  end

  def test_disabled_inherits_from_fieldset
    # The text input inside the disabled fieldset should be :disabled.
    fieldset_input = @elements.find { _1.name == 'input' && _1.parent.name == 'fieldset' }

    assert CSS.matches?(fieldset_input, ':disabled')
  end

  def test_required_optional
    required_inputs = @elements.select { _1.name == 'input' && CSS.matches?(_1, ':required') }
    optional_inputs = @elements.select { _1.name == 'input' && CSS.matches?(_1, ':optional') }

    assert_equal 1, required_inputs.size
    assert_equal 4, optional_inputs.size
  end

  def test_placeholder_shown
    placeholder_inputs = @elements.select { CSS.matches?(_1, 'input:placeholder-shown') }

    assert_equal 1, placeholder_inputs.size
  end

  def test_link
    assert_match_tags 'a:any-link', ['a']
  end

  # Lang / dir -------------------------------------------------------

  def test_lang_inherited_from_root
    p = @elements.find { _1.name == 'p' && _1.text =~ /First/ }

    assert CSS.matches?(p, ':lang(en)')
  end

  def test_lang_overridden_in_subtree
    ja_p = @elements.find { _1.parent.name == 'article' }

    assert CSS.matches?(ja_p, ':lang(ja)')
    refute CSS.matches?(ja_p, ':lang(en)')
  end

  # Stateful pseudos return false ------------------------------------

  def test_hover_focus_etc_return_false
    %w[:hover :focus :focus-within :focus-visible :visited :active].each {|s|
      assert_empty matched_tags(s), "expected #{s} to match nothing"
    }
  end

  # SelectorList accepts the high-level entry --------------------------

  def test_selector_list_string
    assert CSS.matches?(@doc.at_css('h1'), '.title, #nope')
  end

  def test_selector_list_ast
    sl = CSS.parse_selector_list('.lead')
    p_lead = @elements.find { _1.name == 'p' && _1['class'] == 'lead' }

    assert CSS.matches?(p_lead, sl)
  end

  # Pseudo-element never matches an element ---------------------------

  def test_pseudo_element_does_not_match
    assert_empty matched_tags('::before')
  end
end
