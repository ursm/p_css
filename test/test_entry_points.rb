require_relative 'test_helper'

class TestEntryPoints < Minitest::Test
  include CSS::Nodes

  # parse_rule -----------------------------------------------------------

  def test_parse_rule_qualified
    rule = CSS.parse_rule('  a { color: red; }  ')

    assert_kind_of QualifiedRule, rule
    assert_equal [CSS::Token.new(:ident, 'a')], rule.prelude
  end

  def test_parse_rule_at_rule
    rule = CSS.parse_rule('@media (min-width: 600px) { body {} }')

    assert_kind_of AtRule, rule
    assert_equal 'media', rule.name
  end

  def test_parse_rule_empty_input_raises
    assert_raises(CSS::ParseError) { CSS.parse_rule('') }
    assert_raises(CSS::ParseError) { CSS.parse_rule('   ') }
  end

  def test_parse_rule_trailing_tokens_raises
    assert_raises(CSS::ParseError) { CSS.parse_rule('a {} b {}') }
  end

  def test_parse_rule_qualified_without_block_raises
    assert_raises(CSS::ParseError) { CSS.parse_rule('a, b') }
  end

  # parse_declaration ----------------------------------------------------

  def test_parse_declaration_basic
    decl = CSS.parse_declaration('color: red')

    assert_equal 'color',                     decl.name
    assert_equal CSS::Token.new(:ident, 'red'), decl.value.first
    refute decl.important
  end

  def test_parse_declaration_important
    decl = CSS.parse_declaration('color: red !important')

    assert decl.important
  end

  def test_parse_declaration_custom_property
    decl = CSS.parse_declaration('--brand: rgb(0, 0, 0)')

    assert_equal '--brand', decl.name
    assert_kind_of Function, decl.value.first
  end

  def test_parse_declaration_invalid_raises
    assert_raises(CSS::ParseError) { CSS.parse_declaration('') }
    assert_raises(CSS::ParseError) { CSS.parse_declaration('not-a-declaration') }
    assert_raises(CSS::ParseError) { CSS.parse_declaration('123: red') }
  end

  # parse_block_contents -------------------------------------------------

  def test_parse_block_contents_style_attribute
    block = CSS.parse_block_contents('color: red; background: blue;')

    assert_equal 2,           block.items.size
    assert_equal 'color',     block.items[0].name
    assert_equal 'background', block.items[1].name
  end

  def test_parse_block_contents_with_nested_rule
    block = CSS.parse_block_contents('color: red; & .x { font-size: 12px; }')

    assert_equal 2,                block.items.size
    assert_kind_of Declaration,   block.items[0]
    assert_kind_of QualifiedRule, block.items[1]
  end

  def test_parse_block_contents_skips_stray_close_brace
    block = CSS.parse_block_contents('} color: red; }')

    assert_equal 1,       block.items.size
    assert_equal 'color', block.items.first.name
  end

  def test_parse_block_contents_empty
    block = CSS.parse_block_contents('')

    assert_equal [], block.items
  end

  # parse_component_value ------------------------------------------------

  def test_parse_component_value_function
    cv = CSS.parse_component_value('rgb(1, 2, 3)')

    assert_kind_of Function, cv
    assert_equal   'rgb',    cv.name
  end

  def test_parse_component_value_simple_block
    cv = CSS.parse_component_value('[href]')

    assert_kind_of SimpleBlock, cv
    assert_equal   '[',         cv.open
  end

  def test_parse_component_value_token
    cv = CSS.parse_component_value('  red  ')

    assert_equal CSS::Token.new(:ident, 'red'), cv
  end

  def test_parse_component_value_empty_raises
    assert_raises(CSS::ParseError) { CSS.parse_component_value('') }
  end

  def test_parse_component_value_extra_tokens_raises
    assert_raises(CSS::ParseError) { CSS.parse_component_value('red blue') }
  end

  # parse_component_values -----------------------------------------------

  def test_parse_component_values_preserves_whitespace
    values = CSS.parse_component_values('1px solid red')

    assert_equal 5, values.size
    assert_equal :dimension,  values[0].type
    assert_equal :whitespace, values[1].type
    assert_equal :ident,      values[2].type
  end

  def test_parse_component_values_empty
    assert_equal [], CSS.parse_component_values('')
  end

  # parse_comma_separated_values -----------------------------------------

  def test_parse_comma_separated_values_three_groups
    groups = CSS.parse_comma_separated_values('1px, 2px, 3px')

    assert_equal 3, groups.size
    assert_kind_of CSS::Token, groups[0].first
    assert_equal :dimension,   groups[0].first.type
  end

  def test_parse_comma_separated_values_empty_input
    assert_equal [[]], CSS.parse_comma_separated_values('')
  end

  def test_parse_comma_separated_values_trailing_comma
    groups = CSS.parse_comma_separated_values('a, b,')

    assert_equal 3, groups.size
    assert_equal [], groups.last
  end
end
