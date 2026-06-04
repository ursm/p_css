require_relative 'test_helper'

class TestNesting < Minitest::Test
  def desugar(src)
    CSS.serialize(CSS.desugar(CSS.parse_stylesheet(src))).strip
  end

  def assert_desugars(input, expected)
    actual = desugar(input)

    assert_equal expected, actual,
                 "desugaring of #{input.inspect} differed"
  end

  def test_passthrough_when_no_nesting
    assert_desugars(
      '.a { color: red; }',
      ".a {\n  color: red;\n}"
    )
  end

  def test_explicit_ampersand_descendant
    assert_desugars(
      '.a { & .b { color: red; } }',
      ".a .b {\n  color: red;\n}"
    )
  end

  def test_implicit_ampersand_descendant
    assert_desugars(
      '.a { .b { color: red; } }',
      ".a .b {\n  color: red;\n}"
    )
  end

  def test_compound_nesting_inlines_components
    assert_desugars(
      '.a { &.x { color: red; } }',
      ".a.x {\n  color: red;\n}"
    )
  end

  def test_descendant_then_compound
    assert_desugars(
      '.a { & .b.x { color: red; } }',
      ".a .b.x {\n  color: red;\n}"
    )
  end

  def test_parent_with_combinator_descendant_child
    assert_desugars(
      '.a > .b { & .c { color: red; } }',
      ".a > .b .c {\n  color: red;\n}"
    )
  end

  def test_parent_with_combinator_compound_uses_is
    assert_desugars(
      '.a > .b { &.x { color: red; } }',
      ":is(.a > .b).x {\n  color: red;\n}"
    )
  end

  def test_multi_parent_descendant_uses_is
    assert_desugars(
      '.a, .b { & .c { color: red; } }',
      ":is(.a, .b) .c {\n  color: red;\n}"
    )
  end

  def test_multi_parent_compound_uses_is
    assert_desugars(
      '.a, .b { &.x { color: red; } }',
      ":is(.a, .b).x {\n  color: red;\n}"
    )
  end

  def test_parent_declarations_emerge_first
    out = desugar('.a { & .b { color: blue; } color: red; }')

    lines = out.lines

    assert_match(/\A\.a \{/,    lines[0])
    assert_match(/\.a \.b \{/,  out)
    assert_match(/color: red;/, out[/\.a \{[^}]+\}/])
  end

  def test_nested_at_media_wraps_parent
    assert_desugars(<<~CSS, <<~OUT.chomp)
      .a {
        color: red;
        @media (max-width: 600px) {
          color: blue;
        }
      }
    CSS
      .a {
        color: red;
      }
      @media (max-width: 600px) {
        .a {
          color: blue;
        }
      }
    OUT
  end

  def test_nested_at_media_with_further_nesting
    out = desugar(<<~CSS)
      .a {
        @media (max-width: 600px) {
          color: blue;
          & .child { color: green; }
        }
      }
    CSS

    assert_match(/@media \(max-width: 600px\) \{/, out)
    assert_match(/\.a \{[^}]*color: blue;[^}]*\}/m, out)
    assert_match(/\.a \.child \{[^}]*color: green;/m, out)
  end

  def test_three_levels_deep
    assert_desugars(
      '.a { & .b { & .c { color: red; } } }',
      ".a .b .c {\n  color: red;\n}"
    )
  end

  def test_three_levels_deep_implicit
    assert_desugars(
      '.a { .b { .c { color: red; } } }',
      ".a .b .c {\n  color: red;\n}"
    )
  end

  def test_pseudo_class_with_ampersand
    assert_desugars(
      '.a { &:hover { color: red; } }',
      ".a:hover {\n  color: red;\n}"
    )
  end

  def test_top_level_at_rule_with_nesting_inside
    out = desugar(<<~CSS)
      @media (max-width: 600px) {
        .a {
          & .b { color: red; }
        }
      }
    CSS

    assert_match(/@media/,           out)
    assert_match(/\.a \.b \{/,        out)
  end

  def test_top_level_at_rule_without_qualified_rule_unchanged
    src = "@charset \"UTF-8\";"

    assert_equal src, desugar(src)
  end

  # Combinator-led nesting (the nested prelude starts with a combinator,
  # implying a leading `&`).

  def test_combinator_led_nesting_child
    assert_desugars(
      '.a { > .c { color: red; } }',
      ".a > .c {\n  color: red;\n}"
    )
  end

  def test_combinator_led_nesting_sibling_combinators
    assert_desugars('.a { + .c { x: 1; } }', ".a + .c {\n  x: 1;\n}")
    assert_desugars('.a { ~ .c { x: 1; } }', ".a ~ .c {\n  x: 1;\n}")
  end

  def test_combinator_led_nesting_multi_compound_parent
    assert_desugars(
      '.a .b { > .c { x: 1; } }',
      ".a .b > .c {\n  x: 1;\n}"
    )
  end

  def test_combinator_led_nesting_multi_selector_parent_uses_is
    assert_desugars(
      '.a, .b { > .c { x: 1; } }',
      ":is(.a, .b) > .c {\n  x: 1;\n}"
    )
  end

  def test_top_level_leading_combinator_is_still_invalid
    assert_raises(CSS::ParseError) { CSS.parse_selector_list('> .c') }
  end

  def test_re_desugar_is_idempotent
    src = '.a { & .b { & .c { color: red; } } }'
    once  = desugar(src)
    twice = desugar(once)

    assert_equal once, twice
  end
end
