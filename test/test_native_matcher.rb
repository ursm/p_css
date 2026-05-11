require_relative 'test_helper'
require 'css/native'
require 'nokogiri'

# Differential parity test for CSS::Native against the pure-Ruby Matcher.
# Pseudo-classes are out of scope for this Phase — those selectors fall
# back to pure Ruby and are exercised in test_matcher.rb.
class TestNativeMatcher < Minitest::Test
  HTML = <<~HTML.freeze
    <html lang="en">
      <body>
        <header class="site">
          <h1 id="t" class="title">Hello</h1>
          <a href="/about" class="link">About</a>
        </header>
        <main class="main">
          <article data-state="active" data-tag="warn">
            <h2 class="title sub">Section</h2>
            <p class="lead">First paragraph.</p>
            <p>Second.</p>
            <ul>
              <li class="x">a</li>
              <li class="y">b</li>
              <li>c</li>
            </ul>
            <a href="https://example.com" class="link external">Out</a>
          </article>
          <form>
            <input type="text"     name="q"     placeholder="search">
            <input type="checkbox" name="t1"    required>
            <input type="checkbox" name="t2">
            <button type="submit" disabled>Send</button>
          </form>
        </main>
      </body>
    </html>
  HTML

  SELECTORS = [
    '*',
    'a',
    'div',
    'h1',
    '.title',
    '.title.sub',
    '.link',
    '#t',
    '[href]',
    '[data-state="active"]',
    '[data-state=active]',
    '[data-tag*="war"]',
    '[data-tag^="war"]',
    '[data-tag$="rn"]',
    '[data-tag~="warn"]',
    '[type="checkbox"]',
    '[data-tag="WARN" i]',
    'a.link',
    'article p',
    'article > p',
    'ul li',
    'ul > li',
    'h1 + a',
    'h1 ~ a',
    '.main .title',
    'body header .link',
    'article [data-state]'
  ].freeze

  def setup
    @doc      = Nokogiri::HTML(HTML)
    @elements = []
    @doc.traverse {|n| @elements << n if n.element? }
    @snap = CSS::Native::Snapshot.from_document(@doc)
  end

  SELECTORS.each_with_index do |selector_src, i|
    define_method(:"test_parity_#{i.to_s.rjust(2, '0')}_#{selector_src.gsub(/\W+/, '_')}") do
      assert_parity(selector_src)
    end
  end

  private

  def assert_parity(selector_src)
    ast      = CSS.parse_selector_list(selector_src)
    compiled = CSS::Native::Selector.compile(ast)

    @elements.each do |el|
      native = @snap.matches?(el, compiled)
      ruby   = CSS.matches?(el, ast)

      assert_equal ruby, native,
                   "selector #{selector_src.inspect} on <#{el.name}> #{el.attributes.values.map(&:value).inspect} " \
                   "expected #{ruby} got #{native}"
    end
  end
end
