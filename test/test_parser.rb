require_relative 'test_helper'

class TestParser < Minitest::Test
  include CSS::Nodes

  def parse(input)
    CSS.parse(input)
  end

  def test_empty_stylesheet
    assert_equal Stylesheet.new(rules: []), parse('')
  end

  def test_single_qualified_rule
    ss = parse('a { color: red; }')

    assert_equal 1, ss.rules.size

    rule = ss.rules.first

    assert_kind_of QualifiedRule,                       rule
    assert_equal [CSS::Token.new(:ident, 'a')],         rule.prelude
    assert_equal 1,                                     rule.block.items.size
    assert_equal Declaration.new(
      name:      'color',
      value:     [CSS::Token.new(:ident, 'red')],
      important: false
    ), rule.block.items.first
  end

  def test_multiple_declarations_and_important
    ss = parse('.x { color: red; background: #fff !important; }')

    items = ss.rules.first.block.items

    assert_equal 2,           items.size
    assert_equal 'color',     items[0].name
    refute                    items[0].important
    assert_equal 'background', items[1].name
    assert items[1].important
    assert_equal CSS::Token.new(:hash, 'fff', flag: :id), items[1].value.first
  end

  def test_at_rule_without_block
    ss = parse('@charset "UTF-8";')

    rule = ss.rules.first

    assert_kind_of AtRule, rule
    assert_equal 'charset', rule.name
    assert_nil rule.block
    assert_equal [CSS::Token.new(:string, 'UTF-8')], rule.prelude
  end

  def test_at_rule_with_block
    ss = parse('@media (min-width: 600px) { body { color: red; } }')

    media = ss.rules.first

    assert_kind_of AtRule,        media
    assert_equal   'media',       media.name
    refute_nil     media.block

    inner = media.block.items.first

    assert_kind_of QualifiedRule,                inner
    assert_equal   [CSS::Token.new(:ident, 'body')], inner.prelude
  end

  def test_function_in_value
    decl = parse('a { color: rgb(255, 0, 0); }').rules.first.block.items.first

    fn = decl.value.first

    assert_kind_of Function, fn
    assert_equal   'rgb',    fn.name

    nums = fn.value.select {|v| v.respond_to?(:type) && v.type == :number }

    assert_equal [255, 0, 0], nums.map(&:value)
  end

  def test_ignores_top_level_cdo_cdc
    ss = parse('<!-- a {} -->')

    assert_equal 1, ss.rules.size
  end

  def test_nesting_with_ampersand
    ss = parse(<<~CSS)
      .card {
        padding: 1em;
        & .title { color: red; }
      }
    CSS

    items = ss.rules.first.block.items

    assert_equal 2,           items.size
    assert_kind_of Declaration,   items[0]
    assert_kind_of QualifiedRule, items[1]
    assert_equal CSS::Token.new(:delim, '&'), items[1].prelude.first
  end

  def test_nesting_disambiguation_a_hover
    ss = parse(<<~CSS)
      .card {
        color: black;
        a:hover { color: red; }
      }
    CSS

    items = ss.rules.first.block.items

    assert_equal 2, items.size
    assert_kind_of Declaration,   items[0]
    assert_equal   'color',       items[0].name
    assert_kind_of QualifiedRule, items[1]

    sel = items[1].prelude

    assert_equal :ident, sel[0].type
    assert_equal 'a',    sel[0].value
    assert_equal :colon, sel[1].type
    assert_equal :ident, sel[2].type
    assert_equal 'hover', sel[2].value
  end

  def test_deeply_nested
    ss = parse(<<~CSS)
      .a {
        & .b {
          & .c { color: red; }
        }
      }
    CSS

    a = ss.rules.first
    b = a.block.items.first
    c = b.block.items.first

    assert_kind_of QualifiedRule, c
    assert_equal   'color',       c.block.items.first.name
  end

  def test_nested_at_rule_inside_qualified_rule
    ss = parse(<<~CSS)
      .a {
        color: black;
        @media (min-width: 600px) {
          color: red;
        }
      }
    CSS

    items = ss.rules.first.block.items

    assert_equal 2, items.size
    assert_kind_of AtRule, items[1]
    assert_equal 'media', items[1].name
    assert_kind_of Declaration, items[1].block.items.first
  end

  def test_custom_property
    ss = parse(':root { --my-color: red; }')

    decl = ss.rules.first.block.items.first

    assert_equal '--my-color', decl.name
    assert_equal CSS::Token.new(:ident, 'red'), decl.value.first
  end

  def test_unterminated_block_is_tolerated
    ss = parse('a { color: red; ')

    rule = ss.rules.first

    assert_kind_of QualifiedRule, rule
    assert_equal 1, rule.block.items.size
  end

  def test_simple_block_in_prelude
    ss = parse('a[href="x"] { color: red; }')

    rule = ss.rules.first

    assert_kind_of QualifiedRule, rule
    assert(rule.prelude.any? {|p| p.is_a?(SimpleBlock) && p.open == '[' })
  end
end
