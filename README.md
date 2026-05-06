# p CSS

A CSS toolkit for Ruby — tokenizer, parser, serializer, selector matcher, and
cascade resolver. Targets CSS Syntax Level 4 (with nesting), Selectors Level 4,
and Media Queries Level 4.

The name reads as **p CSS** — Ruby's `p` method (puts-inspect) applied to CSS.
Installed under the gem name `p_css`; the top-level module is `CSS`.

```ruby
require 'p_css'

CSS.parse_stylesheet('.foo { color: red }')
```

## Why this exists

The Ruby ecosystem already has a few CSS parsers (crass, sass-rb's grammar,
nokogiri's selector-to-XPath compiler), but each stops at a different layer
and none of them currently:

- parse modern CSS nesting (`& .child { ... }`),
- expose a Selectors Level 4 AST you can inspect,
- match selectors against a DOM in pure Ruby,
- resolve the cascade so `display: none` in a `<style>` tag actually
  influences a visibility judgement.

p CSS fills that gap. The first concrete user is
[capybara-simulated](https://github.com/ursm/capybara-simulated) (a
Nokogiri + QuickJS Capybara driver that needs to know whether an element
is hidden without a real browser), but the gem is intentionally general —
no DOM library is hardwired in.

## What's in the box

| Layer | Entry point | Spec |
| --- | --- | --- |
| Tokenizer | `CSS.tokenize` | Syntax 4 §4 |
| Parser (with nesting) | `CSS.parse_stylesheet` and §5.3 entry points | Syntax 4 §5, Nesting 1 |
| Serializer (round-trip) | `CSS.serialize` | Syntax 4 §9 |
| `urange` | `CSS.parse_urange` | Syntax 4 §6 |
| Selector parser | `CSS.parse_selector_list`, `CSS.parse_selector` | Selectors 4 |
| AnB microsyntax | `CSS.parse_anb` | Syntax 4 §6.7 |
| Specificity | `CSS.specificity` | Selectors §16 |
| Selector matcher | `CSS.matches?` | Selectors 4 |
| Nesting de-sugar | `CSS.desugar` | Nesting 1 |
| Media query parser | `CSS.parse_media_query_list` | Media Queries 4 |
| Media query evaluator | `CSS.media_matches?` | Media Queries 4 |
| Cascade resolver | `CSS.cascade(...).resolve(element)` | Cascade & Inheritance 4 (subset) |

## Install

```ruby
# Gemfile
gem 'p_css'
```

Or:

```sh
bundle add p_css
```

Ruby 3.4+ is required. The matcher works against any object that quacks like
a DOM element (`Nokogiri::XML::Element` works out of the box); Nokogiri is not
a hard dependency.

## Quick tour

### Parse a stylesheet

```ruby
ss = CSS.parse_stylesheet(<<~CSS)
  .card, .panel {
    color: red;
    & .title { font-weight: 700; }
    @media (min-width: 600px) { padding: 2rem; }
  }
CSS

ss.rules.size                     # => 1
ss.rules.first.block.items.count  # => 3 (1 declaration + 1 nested rule + 1 nested at-rule)
```

`CSS.parse` is an alias of `CSS.parse_stylesheet`.

### Round-trip

`CSS.serialize` accepts any AST node, Token, or array of component values, and
emits CSS that re-parses to the same AST.

```ruby
src = '.foo { color: #abc; & .x { font-weight: 700 !important; } }'
CSS.serialize(CSS.parse_stylesheet(src))
# => ".foo {\n  color: #abc;\n  & .x {\n    font-weight: 700 !important;\n  }\n}"
```

### Spec entry points

```ruby
CSS.parse_rule('@charset "UTF-8";')                  # one rule
CSS.parse_declaration('color: red !important')       # one declaration
CSS.parse_block_contents('color: red; padding: 1em') # for `style="..."` etc.
CSS.parse_component_value('rgb(1, 2, 3)')            # one component value
CSS.parse_component_values('1px solid red')          # array of component values
CSS.parse_comma_separated_values('1px, 2px, 3px')    # array of arrays
```

### Comments and source positions

```ruby
ts = CSS.tokenize("a /* hi */ b\n c", preserve_comments: true)
ts.map { [it.type, it.value, it.position.to_s] }
# => [[:ident, "a", "1:1"],
#     [:whitespace, nil, "1:2"],
#     [:comment, " hi ", "1:3"],
#     ...]
```

`Token#position` is set during tokenization (`line`, `column`, `offset`,
`end_offset`). Equality on `Token` ignores position, so hand-built tokens still
compare equal to parsed ones.

`ParseError#position` carries the same information, and the message is prefixed
`line:col:` when available.

### Selectors

```ruby
sl = CSS.parse_selector_list('.card > a:hover, [data-x="y" i]:nth-child(2n+1)')
sl.selectors.size                   # => 2
sl.selectors[0].combinators         # => [:child]

compound = sl.selectors[1].compounds[0]
attr = compound.components[0]
attr.matcher                        # => :exact
attr.case_flag                      # => :i

nth = compound.components[1]
nth.argument                        # => CSS::Selectors::AnB(step: 2, offset: 1)
```

The selector parser also accepts the prelude of a parsed rule directly (the
prelude can contain `Function` / `SimpleBlock` nodes from the main parser; they
are flattened back into a token stream automatically):

```ruby
ss = CSS.parse_stylesheet('.x { ... }')
CSS.parse_selector_list(ss.rules.first.prelude)
```

### Specificity

```ruby
CSS.specificity(CSS.parse_selector_list('div.a#b')) # => Specificity(1, 1, 1)
CSS.specificity(CSS.parse_selector_list(':where(#x)')) # => Specificity(0, 0, 0)
CSS.specificity(CSS.parse_selector_list(':is(.a, #b)')) # => Specificity(1, 0, 0)
```

`Specificity` is `Comparable`, so `>`, `<`, `==` work as expected.

### Matcher

`CSS.matches?(element, selector)` checks whether a duck-typed element matches a
selector. The element must respond to `name` (or `tag_name`), `[]`, `parent`,
sibling navigation (`previous_element` / `next_element` if defined; otherwise
`previous_sibling` / `next_sibling`), and `children`. Nokogiri elements satisfy
this without any wrapping.

```ruby
require 'nokogiri'

doc = Nokogiri::HTML(<<~HTML)
  <ul>
    <li>one</li>
    <li class="active">two</li>
    <li>three</li>
  </ul>
HTML

active = doc.at_css('li.active')
CSS.matches?(active, 'li:nth-child(2n)')                 # => true
CSS.matches?(active, ':is(.active, .selected)')          # => true
CSS.matches?(active, 'ul > li:not(:first-child)')        # => true
```

Stateful pseudo-classes (`:hover`, `:focus`, `:visited`, validity API states,
etc.) deliberately return `false` — this matcher is intended for stateless
analysis. `:has()` is not yet implemented (its argument is kept as opaque
component values).

### Nesting de-sugar

`CSS.desugar` returns a flat Stylesheet with `&` substituted by the parent
selector. Single-compound parents inline directly; multi-selector parents
collapse to `:is(...)`.

```ruby
src = <<~CSS
  .card, .panel {
    color: red;
    & .title { font-weight: 700; }
  }
CSS

CSS.serialize(CSS.desugar(CSS.parse_stylesheet(src)))
# .card, .panel {
#   color: red;
# }
# :is(.card, .panel) .title {
#   font-weight: 700;
# }
```

### Media queries

```ruby
ql = CSS.parse_media_query_list('screen and (600px <= width < 1200px)')

ctx = CSS::MediaQueries::Context.default('width' => 800)
CSS.media_matches?(ql, ctx)         # => true

ctx = CSS::MediaQueries::Context.default('width' => 1500)
CSS.media_matches?(ql, ctx)         # => false
```

`Context` is a feature-name-keyed Hash with sensible defaults (1024×768
landscape light-mode screen). Override per call:

```ruby
ctx = CSS::MediaQueries::Context.default(
  'width' => 1200,
  'prefers-color-scheme' => 'dark'
)
```

Length units (px, em, rem, pt, pc, in, cm, mm, Q) are converted to CSS px
against a 16-px root assumption; resolution units (dppx, x, dpi, dpcm) to
dppx.

### Cascade

`Cascade` resolves the winning declaration per property for one element.
Construct once per stylesheet (selectors, media queries, and specificities are
pre-computed); call `resolve(element)` cheaply per element.

```ruby
ss = CSS.parse_stylesheet(<<~CSS)
  p { color: black; }
  .lead { color: blue; }
  p.special { color: red !important; }
  @media (max-width: 600px) {
    .lead { font-size: 0.875rem; }
  }
CSS

ctx     = CSS::MediaQueries::Context.default('width' => 1024)
cascade = CSS.cascade(ss, context: ctx)

el = Nokogiri::HTML('<p class="lead special">…</p>').at_css('p')
winners = cascade.resolve(el, inline_style: el['style'])

CSS.serialize(winners['color'].value)   # => "red"
winners['color'].important              # => true
winners['font-size']                    # => nil  (only fires for max-width: 600px)
```

The cascade sort follows: `!important` > inline > stylesheet > specificity >
source order. Cascade layers, `@scope` proximity, and Shadow DOM
encapsulation are not modeled — `@layer` / `@supports` / `@scope` /
`@container` / `@starting-style` blocks are descended into unconditionally.

### `urange`

```ruby
r = CSS.parse_urange('U+10??')
r.first      # => 0x1000
r.last       # => 0x10FF
r.cover?(0x10AB)  # => true
r.to_s       # => "U+1000-10FF"
```

## Out of scope

These are deliberate omissions; pull requests welcome:

- Selectors Level 4 namespace prefixes (`ns|*`)
- The column combinator `||`
- `:has()` (relative selector list — needs a small AST extension)
- Strict/forgiving selector list distinction
- `@scope` proximity and the rest of the Cascade Layers spec
- Layout calculations (`display: block` vs flex sizing, `overflow: hidden`
  clipping). p CSS reports the resolved property values; deciding whether
  those values produce a zero-sized box is outside its scope.

## Compatibility

Ruby 3.4+. Tested on the current MRI. No mandatory runtime dependencies.

## License

MIT.
