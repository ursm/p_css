require_relative 'test_helper'
require 'nokogiri'

class TestQuery < Minitest::Test
  HTML = <<~HTML
    <div id="root">
      <div class="row" id="r1">
        <span class="cell">a</span>
        <span class="cell sel">b</span>
        <em><span class="cell">deep</span></em>
      </div>
      <div class="row" id="r2">
        <span class="cell">c</span>
      </div>
    </div>
  HTML

  def setup
    @doc  = Nokogiri::HTML::DocumentFragment.parse(HTML)
    @root = @doc.at_css('#root')
    @r1   = @doc.at_css('#r1')
    @r2   = @doc.at_css('#r2')
  end

  def texts(nodes) = nodes.map { _1.text.strip }

  def test_select_all_descendants_in_document_order
    cells = CSS.select_all(@root, '.cell')

    assert_equal %w[a b deep c], texts(cells)
  end

  def test_select_all_excludes_the_root_itself
    rows = CSS.select_all(@root, '.row')

    assert_equal %w[r1 r2], rows.map { _1['id'] }
  end

  def test_select_first_returns_first_in_order
    assert_equal 'a', CSS.select_first(@root, '.cell').text.strip
    assert_nil        CSS.select_first(@root, '.nonexistent')
  end

  def test_select_all_over_multiple_roots_dedups
    cells = CSS.select_all([@r1, @root], '.cell')

    # @r1's cells (a, b, deep) come first; @root then contributes only the
    # not-yet-seen cell (c) — each node appears exactly once.
    assert_equal %w[a b deep c], texts(cells)
    assert_equal cells.size, cells.uniq.size
  end

  def test_closest_inclusive_ancestor
    deep = @doc.at_css('em .cell')

    assert_equal 'r1', CSS.closest(deep, '.row')['id']
    # Inclusive: the element itself can be the match.
    assert_equal deep, CSS.closest(deep, '.cell')
    assert_nil         CSS.closest(deep, '.nope')
  end

  # :scope ----------------------------------------------------------

  def test_scope_matches_supplied_roots
    # `:scope > .cell` within @r1 resolves only @r1's direct cells (not the
    # one nested in <em>, and not @r2's).
    cells = CSS.select_all(@root, ':scope > .cell', scope: @r1)

    assert_equal %w[a b], texts(cells)
  end

  def test_scope_accepts_array_of_roots
    cells = CSS.select_all(@root, ':scope > .cell', scope: [@r1, @r2])

    assert_equal %w[a b c], texts(cells)
  end

  def test_scope_falls_back_to_root_without_option
    # With no scope, `:scope` behaves like `:root`: @root has no element
    # parent (its parent is the fragment), so it matches; @r1 does not.
    assert CSS.matches?(@root, ':scope')
    refute CSS.matches?(@r1, ':scope')
  end

  def test_matches_with_scope_option
    assert CSS.matches?(@r1, ':scope', scope: @r1)
    refute CSS.matches?(@r2, ':scope', scope: @r1)
  end
end
