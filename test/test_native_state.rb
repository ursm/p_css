require_relative 'test_helper'
require 'css/native'
require 'nokogiri'

# Differential parity for the stateful pseudo branch: native and the
# pure-Ruby Matcher should agree on :hover / :focus / :visited / :active
# / :focus-within / :focus-visible / :target across the same `state:`
# input.
class TestNativeState < Minitest::Test
  HTML = <<~HTML.freeze
    <html><body>
      <nav>
        <a href="/a" class="link">A</a>
        <a href="/b" class="link visited">B</a>
      </nav>
      <main>
        <article>
          <h1>Title</h1>
          <p class="lead">First.</p>
          <form>
            <input type="text" name="q">
            <button type="submit">Submit</button>
          </form>
        </article>
      </main>
    </body></html>
  HTML

  def setup
    @doc      = Nokogiri::HTML(HTML)
    @elements = []
    @doc.traverse {|n| @elements << n if n.element? }
    @snap     = CSS::Native::Snapshot.from_document(@doc)
  end

  # Non-propagating pseudos: state must list exactly the element to match.
  def test_focus_matches_only_listed_element
    input = @doc.at('input')
    assert_state_parity ':focus', {focus: [input]}
  end

  # Propagating pseudos: state lists "source" elements, and every ancestor
  # also matches.
  def test_hover_propagates_to_ancestors
    button = @doc.at('button')
    assert_state_parity ':hover', {hover: [button]}
  end

  def test_active_propagates_to_ancestors
    link = @doc.at('a.link.visited')
    assert_state_parity ':active', {active: [link]}
  end

  def test_focus_within_propagates_to_ancestors
    input = @doc.at('input')
    assert_state_parity ':focus-within', {'focus-within' => [input]}
  end

  # `true` state means "every element matches"
  def test_all_state_true
    assert_state_parity ':hover', {hover: true}
  end

  # `nil` / `false` / missing key → no element matches.
  def test_no_state
    assert_state_parity ':hover', nil
    assert_state_parity ':hover', {hover: nil}
    assert_state_parity ':hover', {hover: false}
  end

  # State keys can be either Symbol or String.
  def test_string_keys
    input = @doc.at('input')
    assert_state_parity ':focus', {'focus' => [input]}
  end

  # Visited is non-propagating per spec.
  def test_visited_is_not_propagated
    link = @doc.at('a.link.visited')
    assert_state_parity ':visited', {visited: [link]}
  end

  # Combined with other selectors.
  def test_compound_with_state
    button = @doc.at('button')
    assert_state_parity 'button:hover', {hover: [button]}
    assert_state_parity ':not(:hover)',  {hover: [button]}
    assert_state_parity 'main :focus',   {focus: [@doc.at('input')]}
  end

  private

  def assert_state_parity(selector_src, state)
    ast      = CSS.parse_selector_list(selector_src)
    compiled = CSS::Native::Selector.compile(ast)
    native_s = state.nil? ? nil : @snap.compile_state(state)

    @elements.each do |el|
      ruby   = CSS.matches?(el, ast,      state: state)
      native = @snap.matches?(el, compiled, native_s)

      assert_equal ruby, native,
                   "#{selector_src.inspect} with state #{state.inspect} on <#{el.name}> " \
                   "expected #{ruby} got #{native}"
    end
  end
end
