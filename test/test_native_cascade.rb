require_relative 'test_helper'
require 'css/native'
require 'nokogiri'

# Differential parity test: CSS::Native::Cascade#resolve must produce the
# same winning declarations as CSS::Cascade#resolve for every element in
# the document, including styles routed through the Ruby fallback path
# (pseudo-class selectors).
class TestNativeCascade < Minitest::Test
  STYLESHEET_SOURCE = <<~CSS.freeze
    * { box-sizing: border-box; }
    body { color: #333; }
    a { color: blue; }
    .title { font-weight: bold; }
    .title.sub { font-size: 1.1rem; }
    .link { text-decoration: underline; }
    #main { background: white; }
    [data-state="active"] { outline: 2px solid; }
    [data-tag*="war"] { color: orange; }
    article p { line-height: 1.5; }
    article > p { margin: 0; }
    ul > li { padding: 2px; }
    h1 + a { margin-left: 1rem; }
    .main .title { color: black; }
    /* pseudo-class branch — exercises the Ruby fallback */
    p.lead:first-child { font-style: italic; }
    li:nth-child(odd) { background: #f0f0f0; }
    a:not(.external) { color: green; }
  CSS

  HTML = <<~HTML.freeze
    <html><body>
      <main class="main" id="main">
        <header>
          <h1 class="title">Hi</h1>
          <a href="/about" class="link">About</a>
        </header>
        <article data-state="active" data-tag="warn">
          <h2 class="title sub">Section</h2>
          <p class="lead">First.</p>
          <p>Second.</p>
          <ul>
            <li>a</li>
            <li>b</li>
            <li>c</li>
          </ul>
          <a href="//ext" class="link external">Out</a>
        </article>
      </main>
    </body></html>
  HTML

  def setup
    @stylesheet = CSS.parse_stylesheet(STYLESHEET_SOURCE)
    @doc        = Nokogiri::HTML(HTML)
    @context    = CSS::MediaQueries::Context.default
    @elements   = []
    @doc.traverse {|n| @elements << n if n.element? }
  end

  def test_resolve_parity_across_every_element
    ruby_c   = CSS::Cascade.new(@stylesheet, context: @context)
    native_c = CSS::Native::Cascade.new(@stylesheet, @doc, context: @context)

    @elements.each do |el|
      r = ruby_c.resolve(el)
      n = native_c.resolve(el)

      assert_equal r.keys.sort, n.keys.sort,
                   "winning property names differ for <#{el.name}>"

      r.each do |name, decl|
        assert_equal decl, n[name],
                     "<#{el.name}> property #{name.inspect} declaration differs"
      end
    end
  end
end
