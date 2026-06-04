require_relative 'test_helper'

class TestTokenizer < Minitest::Test
  def types(input)
    CSS.tokenize(input).map(&:type)
  end

  def tokens(input)
    CSS.tokenize(input)
  end

  def test_empty_input
    assert_equal [], tokens('')
  end

  def test_idents_and_whitespace
    ts = tokens('foo  bar')

    assert_equal [:ident, :whitespace, :ident],  ts.map(&:type)
    assert_equal %w[foo bar],                    ts.reject {|t| t.type == :whitespace }.map(&:value)
  end

  def test_strings
    assert_equal CSS::Token.new(:string, 'hello'), tokens(%q{'hello'}).first
    assert_equal CSS::Token.new(:string, 'hello'), tokens(%q{"hello"}).first
  end

  def test_string_with_escape
    assert_equal CSS::Token.new(:string, 'a©b'), tokens(%q{"a\\0000a9 b"}).first
  end

  def test_bad_string_terminated_by_newline
    ts = tokens(%Q{"abc\nxyz"})

    assert_equal :bad_string, ts.first.type
  end

  def test_hash_id_vs_unrestricted
    ts = tokens('#abc #1ab')

    assert_equal CSS::Token.new(:hash, 'abc', flag: :id),           ts[0]
    assert_equal CSS::Token.new(:hash, '1ab', flag: :unrestricted), ts[2]
  end

  def test_at_keyword_and_delim_at
    ts = tokens('@media @1invalid')

    assert_equal :at_keyword,            ts[0].type
    assert_equal 'media',                ts[0].value
    assert_equal CSS::Token.new(:delim, '@'), ts[2]
    assert_equal :dimension,             ts[3].type
    assert_equal 1,                      ts[3].value
    assert_equal 'invalid',              ts[3].unit
  end

  def test_numbers_and_dimensions_and_percentages
    ts = tokens('0 12 1.5 -1 +2 .5 1e2 1e+2 1e-2 12px 50%')

    nums = ts.reject {|t| t.type == :whitespace }

    assert_equal :number,     nums[0].type
    assert_equal 0,           nums[0].value
    assert_equal :integer,    nums[0].flag

    assert_equal 12,          nums[1].value

    assert_equal :number,     nums[2].flag
    assert_in_delta 1.5,      nums[2].value

    assert_equal(-1,          nums[3].value)
    assert_equal 2,           nums[4].value

    assert_in_delta 0.5,      nums[5].value
    assert_equal :number,     nums[5].flag

    assert_equal :number,     nums[6].flag
    assert_in_delta 100.0,    nums[6].value

    assert_equal :dimension,  nums[9].type
    assert_equal 12,          nums[9].value
    assert_equal 'px',        nums[9].unit

    assert_equal :percentage, nums[10].type
    assert_in_delta 50.0,     nums[10].value
  end

  def test_url_unquoted
    ts = tokens('url(http://example.com/x.png)')

    assert_equal CSS::Token.new(:url, 'http://example.com/x.png'), ts.first
  end

  def test_url_with_whitespace
    ts = tokens('url(  http://example.com/x.png  )')

    assert_equal CSS::Token.new(:url, 'http://example.com/x.png'), ts.first
  end

  def test_url_quoted_is_function
    ts = tokens(%q{url("a.png")})

    assert_equal :function, ts[0].type
    assert_equal 'url',     ts[0].value
    assert_equal :string,   ts[1].type
    assert_equal 'a.png',   ts[1].value
    assert_equal :rparen,   ts[2].type
  end

  def test_function
    ts = tokens('rgb(1, 2)')

    assert_equal :function, ts[0].type
    assert_equal 'rgb',     ts[0].value
  end

  def test_comments_are_skipped
    ts = tokens('a /* comment */ b')

    assert_equal %i[ident whitespace whitespace ident], ts.map(&:type)
  end

  def test_unterminated_comment_eats_to_eof
    ts = tokens('a /* never ends')

    assert_equal %i[ident whitespace], ts.map(&:type)
  end

  def test_cdo_cdc
    ts = tokens('<!-- a -->')

    assert_equal :cdo, ts[0].type
    assert_equal :cdc, ts[-1].type
  end

  def test_punctuation
    assert_equal %i[colon semicolon comma lbracket rbracket lparen rparen lbrace rbrace],
                 types(':;,[]( ) {}').reject {|t| t == :whitespace }
  end

  def test_escaped_ident
    ts = tokens('\\41 BC')

    assert_equal CSS::Token.new(:ident, 'ABC'), ts.first
  end

  def test_crlf_normalized
    ts = tokens("a\r\nb")

    assert_equal %i[ident whitespace ident], ts.map(&:type)
  end

  # §4.3.8 / §4.3.7: `\` at EOF is a valid escape (EOF is not a newline) and
  # consumes to U+FFFD, so `a\` is the ident `a␦` rather than a stray delim.
  def test_trailing_backslash_at_eof_in_ident
    assert_equal CSS::Token.new(:ident, "a�"), tokens('a\\').first
  end

  def test_trailing_backslash_at_eof_in_hash
    t = tokens('#eof\\').first

    assert_equal :hash, t.type
    assert_equal "eof�", t.value
  end
end
