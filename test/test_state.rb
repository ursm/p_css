require_relative 'test_helper'
require 'nokogiri'

class TestState < Minitest::Test
  HTML = <<~HTML
    <html>
      <body>
        <ul class="menu">
          <li class="item">
            <a class="trigger">Open</a>
            <ul class="submenu">
              <li class="entry">Sub</li>
            </ul>
          </li>
          <li class="item idle"><a class="trigger">Idle</a></li>
        </ul>
        <input class="field" type="text">
      </body>
    </html>
  HTML

  def setup
    @doc = Nokogiri::HTML(HTML)
    @menu    = @doc.at_css('.menu')
    @item    = @doc.at_css('.item')
    @idle    = @doc.at_css('.item.idle')
    @trigger = @item.at_css('.trigger')
    @sub     = @doc.at_css('.submenu')
    @entry   = @doc.at_css('.entry')
    @field   = @doc.at_css('.field')
  end

  # Default behavior — stateful pseudos return false ----------------

  def test_hover_returns_false_without_state
    refute CSS.matches?(@item, ':hover')
  end

  def test_focus_returns_false_without_state
    refute CSS.matches?(@field, ':focus')
  end

  # `state: true` — match every element ----------------------------

  def test_hover_true_matches_any_element
    assert CSS.matches?(@item,  ':hover', state: {hover: true})
    assert CSS.matches?(@sub,   ':hover', state: {hover: true})
    assert CSS.matches?(@field, ':hover', state: {hover: true})
  end

  def test_focus_true_matches_any_element
    assert CSS.matches?(@field, ':focus', state: {focus: true})
  end

  # `state: Set` — explicit elements -------------------------------

  def test_hover_with_set_matches_only_listed_and_ancestors
    assert CSS.matches?(@item, ':hover', state: {hover: Set[@item]})
    refute CSS.matches?(@idle, ':hover', state: {hover: Set[@item]})
  end

  def test_focus_with_set_does_not_propagate
    assert CSS.matches?(@field, ':focus', state: {focus: Set[@field]})
    refute CSS.matches?(@menu,  ':focus', state: {focus: Set[@field]})
  end

  def test_array_value_works_like_set
    assert CSS.matches?(@item, ':hover', state: {hover: [@item]})
  end

  # Ancestor propagation -------------------------------------------

  def test_hover_propagates_to_ancestors
    state = {hover: Set[@trigger]}

    assert CSS.matches?(@trigger, ':hover', state: state)
    assert CSS.matches?(@item,    ':hover', state: state)
    assert CSS.matches?(@menu,    ':hover', state: state)

    refute CSS.matches?(@idle,    ':hover', state: state)
    refute CSS.matches?(@sub,     ':hover', state: state)
  end

  def test_focus_within_propagates_to_ancestors
    state = {'focus-within' => Set[@field]}

    assert CSS.matches?(@field, ':focus-within', state: state)
    assert CSS.matches?(@doc.at_css('body'), ':focus-within', state: state)
  end

  def test_active_propagates_to_ancestors
    state = {active: Set[@trigger]}

    assert CSS.matches?(@trigger, ':active', state: state)
    assert CSS.matches?(@menu,    ':active', state: state)
  end

  # Symbol vs String keys ------------------------------------------

  def test_symbol_and_string_keys_are_equivalent
    assert CSS.matches?(@item, ':hover', state: {hover:   Set[@item]})
    assert CSS.matches?(@item, ':hover', state: {'hover' => Set[@item]})
  end

  def test_hyphenated_pseudo_with_string_key
    assert CSS.matches?(@field, ':focus-within', state: {'focus-within' => Set[@field]})
  end

  # Cascade integration --------------------------------------------

  def cascade_for(css)
    CSS.cascade(CSS.parse_stylesheet(css))
  end

  def test_cascade_resolve_with_hover_set
    css = '.submenu { display: none } .item:hover .submenu { display: block }'
    cascade = cascade_for(css)

    no_state = cascade.resolve(@sub)
    hovered  = cascade.resolve(@sub, state: {hover: Set[@item]})

    assert_equal 'none',  CSS.serialize(no_state['display'].value)
    assert_equal 'block', CSS.serialize(hovered['display'].value)
  end

  def test_cascade_resolve_with_hover_true_acts_like_assume_hover
    css = '.x { display: none } .x:hover { display: block }'
    cascade = cascade_for(css)

    el = @doc.create_element('div', class: 'x')

    refute_nil cascade.resolve(el)['display']
    assert_equal 'block', CSS.serialize(cascade.resolve(el, state: {hover: true})['display'].value)
  end

  def test_cascade_resolve_propagation_through_descendant
    css = '.menu:hover .submenu { color: red }'
    cascade = cascade_for(css)

    # Hover at the deeply-nested entry; .menu:hover should still apply.
    state = {hover: Set[@entry]}
    winners = cascade.resolve(@sub, state: state)

    refute_nil winners['color']
    assert_equal 'red', CSS.serialize(winners['color'].value)
  end

  # Recursive selector arguments ----------------------------------

  def test_state_threads_through_is
    state = {hover: Set[@item]}

    assert CSS.matches?(@item, ':is(.item:hover)', state: state)
  end

  def test_state_threads_through_not
    state = {hover: Set[@item]}

    refute CSS.matches?(@item, ':not(:hover)', state: state)
    assert CSS.matches?(@idle, ':not(:hover)', state: state)
  end
end
