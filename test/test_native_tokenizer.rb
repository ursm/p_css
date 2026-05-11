require_relative 'test_helper'
require 'css/native'

# Differential parity test: every input we tokenize with pure Ruby should
# yield equal Tokens (type/value/flag/unit) from CSS::Native.tokenize.
# Position is intentionally not compared yet — Phase 1 only targets shape.
class TestNativeTokenizer < Minitest::Test
  INPUTS = [
    '',
    'foo  bar',
    %q{'hello'},
    %q{"hello"},
    %q{"a\\0000a9 b"},
    %Q{"abc\nxyz"},
    '#abc #1ab',
    '@media @1invalid',
    '0 12 1.5 -1 +2 .5 1e2 1e+2 1e-2 12px 50%',
    'url(http://example.com/x.png)',
    'url(  http://example.com/x.png  )',
    %q{url("a.png")},
    'rgb(1, 2)',
    'a /* comment */ b',
    'a /* never ends',
    '<!-- a -->',
    ':;,[]( ) {}',
    '\\41 BC',
    "a\r\nb"
  ].freeze

  INPUTS.each_with_index do |input, i|
    define_method(:"test_parity_#{i}_#{input.inspect[0, 30].gsub(/\W/, '_')}") do
      ruby_tokens   = CSS.tokenize(input)
      native_tokens = CSS::Native.tokenize(input, false)

      assert_equal ruby_tokens.size, native_tokens.size,
                   "token count differs for #{input.inspect}"

      ruby_tokens.zip(native_tokens).each_with_index {|(r, n), j|
        assert_equal r, n, "token #{j} differs for #{input.inspect}: ruby=#{r.inspect} native=#{n.inspect}"
      }
    end
  end
end
