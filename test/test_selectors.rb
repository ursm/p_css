require_relative 'test_helper'

class TestSelectors < Minitest::Test
  S = CSS::Selectors

  def parse_list(s)   = CSS.parse_selector_list(s)
  def parse_single(s) = CSS.parse_selector(s)
  def round_trip(s)   = CSS.serialize(parse_list(s))

  def first_compound(s)  = parse_list(s).selectors.first.compounds.first
  def first_components(s) = first_compound(s).components

  # Simple selectors --------------------------------------------------

  def test_type_selector
    c = first_components('div').first

    assert_kind_of S::TypeSelector, c
    assert_equal   'div',           c.name
  end

  def test_universal_selector
    assert_kind_of S::UniversalSelector, first_components('*').first
  end

  def test_nesting_selector
    assert_kind_of S::NestingSelector, first_components('&').first
  end

  def test_id_selector
    c = first_components('#foo').first

    assert_kind_of S::IdSelector, c
    assert_equal   'foo',         c.name
  end

  def test_class_selector
    c = first_components('.foo').first

    assert_kind_of S::ClassSelector, c
    assert_equal   'foo',            c.name
  end

  # Compound ----------------------------------------------------------

  def test_compound_type_then_class
    cs = first_components('div.foo')

    assert_equal 2, cs.size
    assert_kind_of S::TypeSelector,  cs[0]
    assert_kind_of S::ClassSelector, cs[1]
  end

  def test_compound_class_chain
    cs = first_components('.a.b.c')

    assert_equal 3, cs.size
    assert(cs.all? { _1.is_a?(S::ClassSelector) })
  end

  # Combinators -------------------------------------------------------

  def test_descendant_combinator
    cs = parse_list('.a .b').selectors.first

    assert_equal [:descendant], cs.combinators
    assert_equal 2,             cs.compounds.size
  end

  def test_child_combinator
    assert_equal [:child], parse_list('.a > .b').selectors.first.combinators
  end

  def test_next_sibling
    assert_equal [:next_sibling], parse_list('.a + .b').selectors.first.combinators
  end

  def test_subsequent_sibling
    assert_equal [:subsequent_sibling], parse_list('.a ~ .b').selectors.first.combinators
  end

  def test_combinators_without_whitespace
    assert_equal [:child], parse_list('.a>.b').selectors.first.combinators
  end

  def test_mixed_combinators
    cs = parse_list('.a > b + c .d').selectors.first

    assert_equal %i[child next_sibling descendant], cs.combinators
    assert_equal 4,                                 cs.compounds.size
  end

  # Selector list -----------------------------------------------------

  def test_selector_list
    sl = parse_list('.a, .b, .c')

    assert_equal 3, sl.selectors.size
  end

  def test_parse_selector_rejects_comma
    assert_raises(CSS::ParseError) { parse_single('.a, .b') }
  end

  # Attribute selectors -----------------------------------------------

  def test_attribute_presence
    a = first_components('[href]').first

    assert_kind_of S::AttributeSelector, a
    assert_equal 'href', a.name
    assert_nil a.matcher
    assert_nil a.value
    assert_nil a.case_flag
  end

  def test_attribute_exact
    a = first_components('[href="x"]').first

    assert_equal :exact, a.matcher
    assert_equal 'x',    a.value
  end

  def test_attribute_unquoted_value
    assert_equal 'x', first_components('[href=x]').first.value
  end

  def test_attribute_all_matchers
    {
      '~' => :includes,
      '|' => :dash,
      '^' => :prefix,
      '$' => :suffix,
      '*' => :substring
    }.each {|op, sym|
      a = first_components(%([href#{op}="x"])).first

      assert_equal sym, a.matcher, "for #{op}="
    }
  end

  def test_attribute_case_flag
    assert_equal :i, first_components('[href*="x" i]').first.case_flag
    assert_equal :s, first_components('[href*="x" s]').first.case_flag
  end

  # Pseudo classes ----------------------------------------------------

  def test_pseudo_class_simple
    p = first_components(':hover').first

    assert_kind_of S::PseudoClass, p
    assert_equal 'hover', p.name
    assert_nil p.argument
  end

  def test_pseudo_element
    p = first_components('::before').first

    assert_kind_of S::PseudoElement, p
    assert_equal 'before', p.name
  end

  def test_pseudo_element_with_argument
    p = first_components('::part(name)').first

    assert_kind_of S::PseudoElement, p
    assert_equal   'part',           p.name
    assert_kind_of Array,            p.argument
  end

  def test_unknown_pseudo_element_is_invalid
    assert_raises(CSS::ParseError) { parse_list('::example') }
  end

  # Namespaces --------------------------------------------------------

  def test_namespace_any_prefix_on_type
    c = first_components('*|div').first

    assert_kind_of S::TypeSelector, c
    assert_equal 'div', c.name
    assert_equal '*',   c.namespace
  end

  def test_namespace_none_prefix_on_type
    c = first_components('|div').first

    assert_equal 'div', c.name
    assert_equal '',    c.namespace
  end

  def test_no_namespace_prefix_is_nil
    assert_nil first_components('div').first.namespace
  end

  def test_namespace_on_universal
    c = first_components('*|*').first

    assert_kind_of S::UniversalSelector, c
    assert_equal '*', c.namespace
  end

  def test_namespace_on_attribute
    c = first_components('[|href]').first

    assert_kind_of S::AttributeSelector, c
    assert_equal 'href', c.name
    assert_equal '',     c.namespace
  end

  def test_dash_attribute_matcher_not_confused_with_namespace
    c = first_components('[a|=b]').first

    assert_kind_of S::AttributeSelector, c
    assert_equal 'a',    c.name
    assert_equal :dash,  c.matcher
    assert_nil           c.namespace
  end

  def test_declared_namespace_prefix_is_rejected
    assert_raises(CSS::ParseError) { parse_list('svg|rect') }
    assert_raises(CSS::ParseError) { parse_list('[svg|attr]') }
  end

  def test_vendor_prefixed_pseudo_element_is_lenient
    p = first_components('::-webkit-scrollbar').first

    assert_kind_of S::PseudoElement, p
    assert_equal '-webkit-scrollbar', p.name
  end

  def test_legacy_single_colon_pseudo_element_stays_pseudo_class
    p = first_components(':before').first

    assert_kind_of S::PseudoClass, p
    assert_equal 'before', p.name
  end

  def test_nth_child_with_anb
    p = first_components(':nth-child(2n+1)').first

    assert_kind_of S::AnB, p.argument
    assert_equal   2,      p.argument.step
    assert_equal   1,      p.argument.offset
    assert_nil     p.argument.of
  end

  def test_nth_child_of_selector
    p = first_components(':nth-child(2n+1 of .x)').first

    assert_kind_of S::AnB,          p.argument
    assert_equal   2,               p.argument.step
    assert_equal   1,               p.argument.offset
    assert_kind_of S::SelectorList, p.argument.of
    assert_equal   '.x',            CSS.serialize(p.argument.of)
  end

  def test_nth_of_type_rejects_of_clause
    assert_raises(CSS::ParseError) { parse_list(':nth-of-type(2n of p)') }
  end

  def test_nth_child_of_selector_round_trip
    assert_equal ':nth-child(2n+3 of .x)', round_trip(':nth-child( 2n + 3 of .x )')
    assert_equal ':nth-child(odd of .x)', round_trip(':nth-child(2n+1 of .x)')
    assert_equal ':nth-child(even of li.a)', round_trip(':nth-child(even of li.a)')
  end

  def test_nth_child_keyword
    assert_equal [2, 0], parse_anb_via_pseudo(':nth-child(even)')
    assert_equal [2, 1], parse_anb_via_pseudo(':nth-child(odd)')
  end

  def parse_anb_via_pseudo(s)
    arg = first_components(s).first.argument
    [arg.step, arg.offset]
  end

  def test_is_with_selector_list
    p = first_components(':is(.a, .b)').first

    assert_kind_of S::SelectorList, p.argument
    assert_equal 2, p.argument.selectors.size
  end

  def test_not_recursive
    p = first_components(':not(:hover)').first

    inner = p.argument.selectors.first.compounds.first.components.first

    assert_kind_of S::PseudoClass, inner
    assert_equal 'hover', inner.name
  end

  def test_has_parses_relative_selector_list
    p = first_components(':has(> .child)').first

    assert_kind_of S::RelativeSelectorList, p.argument

    rel = p.argument.selectors.first

    assert_kind_of S::RelativeSelector, rel
    assert_equal :child, rel.combinator
    assert_kind_of S::ComplexSelector, rel.complex
  end

  def test_has_default_combinator_is_descendant
    rel = first_components(':has(.child)').first.argument.selectors.first

    assert_equal :descendant, rel.combinator
  end

  def test_unknown_functional_pseudo_keeps_tokens
    p = first_components(':lang(en)').first

    assert_kind_of Array, p.argument
  end

  # Round-trip --------------------------------------------------------

  def test_round_trip_basic
    %w[
      *
      &
      div
      .foo
      #bar
      .a.b
      .a\ .b
      .a>.b
      .a+.b
      .a~.b
      [href]
      [data-x="y"]
      :hover
      ::before
      :nth-child(2n+1)
      :is(.a,.b)
      :has(.a)
      :has(>.a)
      :has(+p,~div)
      *|div
      |div
      *|*
      [*|href]
      [|href]
    ].each {|s|
      input = s.gsub('\\ ', ' ')

      out1 = round_trip(input)
      out2 = round_trip(out1)

      assert_equal out1, out2, "round-trip not stable for #{input.inspect}"
    }
  end

  def test_round_trip_via_main_serialize_dispatch
    sl = parse_list('.a > .b')

    assert_equal '.a > .b', CSS.serialize(sl)
  end

  # Errors ------------------------------------------------------------

  def test_empty_raises
    assert_raises(CSS::ParseError) { parse_list('') }
  end

  def test_dangling_dot_raises
    assert_raises(CSS::ParseError) { parse_list('.') }
  end

  def test_unclosed_attribute_raises
    assert_raises(CSS::ParseError) { parse_list('[href') }
  end

  def test_invalid_attribute_matcher_raises
    assert_raises(CSS::ParseError) { parse_list('[href!=x]') }
  end

  def test_pseudo_with_unclosed_function_raises
    assert_raises(CSS::ParseError) { parse_list(':is(.a') }
  end
end
