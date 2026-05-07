require_relative 'test_helper'

class TestComments < Minitest::Test
  include CSS::Nodes

  # Default behavior --------------------------------------------------

  def test_comments_are_stripped_by_default
    types = CSS.tokenize('/* hi */ a').map(&:type)

    refute_includes types, :comment
  end

  def test_default_parse_does_not_preserve_comments
    ss = CSS.parse_stylesheet('/* hi */ a {}')

    refute(ss.rules.any? {|r| r.is_a?(CSS::Token) && r.comment? })
  end

  # Tokenizer ---------------------------------------------------------

  def test_preserve_comments_emits_comment_tokens
    ts = CSS.tokenize('/* hello */ a /* world */', preserve_comments: true)

    comments = ts.select { _1.type == :comment }

    assert_equal 2,         comments.size
    assert_equal ' hello ', comments[0].value
    assert_equal ' world ', comments[1].value
  end

  def test_unterminated_comment_eats_to_eof_with_preserve
    ts = CSS.tokenize('/* never ends', preserve_comments: true)

    assert_equal :comment,        ts.first.type
    assert_equal ' never ends',   ts.first.value
  end

  def test_comment_token_has_position
    pos = CSS.tokenize("a\n/* x */", preserve_comments: true).find { _1.type == :comment }.position

    assert_equal 2, pos.line
    assert_equal 1, pos.column
  end

  # Parser ------------------------------------------------------------

  def test_top_level_comments_appear_in_rules
    ss = CSS.parse_stylesheet('/* a */ a {} /* b */ b {}', preserve_comments: true)

    types = ss.rules.map { _1.is_a?(CSS::Token) ? :comment : :rule }

    assert_equal %i[comment rule comment rule], types
  end

  def test_block_level_comments_appear_in_items
    ss = CSS.parse_stylesheet('a { /* hi */ color: red; /* there */ }', preserve_comments: true)

    items = ss.rules.first.block.items
    types = items.map { _1.is_a?(CSS::Token) ? :comment : _1.class.name }

    assert_includes types, :comment
  end

  def test_prelude_preserves_comments
    rule = CSS.parse_rule('a /* keep */ b {}', preserve_comments: true)

    assert(rule.prelude.any? {|p| p.is_a?(CSS::Token) && p.comment? })
  end

  def test_declaration_value_preserves_comments
    decl = CSS.parse_declaration('color: red /* keep */', preserve_comments: true)

    assert(decl.value.any? {|v| v.is_a?(CSS::Token) && v.comment? })
  end

  def test_important_detection_ignores_trailing_comments
    decl = CSS.parse_declaration('color: red /* hi */ !important', preserve_comments: true)

    assert decl.important
  end

  # Serializer --------------------------------------------------------

  def test_round_trip_with_comments_is_stable
    src = '/* head */ .a /* h */ { color: red /* v */ !important; }'
    ss1 = CSS.parse_stylesheet(src, preserve_comments: true)
    out = CSS.serialize(ss1)
    ss2 = CSS.parse_stylesheet(out, preserve_comments: true)

    assert_equal out, CSS.serialize(ss2)
  end

  def test_serialize_comment_token
    t = CSS::Token.new(:comment, ' x ')

    assert_equal '/* x */', CSS.serialize(t)
  end
end
