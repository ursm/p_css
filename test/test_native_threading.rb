require_relative 'test_helper'
require 'css/native'
require 'nokogiri'

# Sanity check that CSS::Native::Snapshot#matches? releases the GVL — N
# threads should run in parallel and beat single-threaded wall time when
# the machine has multiple cores. We don't assert a hard speedup factor
# (CI runners vary wildly), but we do require that N threads complete
# more matches than 1 thread in the same wall time.
class TestNativeThreading < Minitest::Test
  def test_gvl_released_during_matching
    skip 'needs at least 2 CPU cores' if Etc.respond_to?(:nprocessors) && Etc.nprocessors < 2
    # GitHub Actions runners advertise 2+ vCPUs but the scheduler is
    # noisy and shared — observed ratios go below 1.0 with the same
    # binary that scales to 1.4× on dev hardware. The test is a
    # local-only sanity check.
    skip 'unreliable under CI scheduling' if ENV['CI']

    html = '<html><body>' + ('<div class="a"><p class="b">x</p></div>' * 50) + '</body></html>'
    doc  = Nokogiri::HTML(html)
    snap = CSS::Native::Snapshot.from_document(doc)
    # Inflate the per-call work so the cost of releasing/reacquiring the
    # GVL is small compared to the matching itself.
    selector_sources = 100.times.flat_map {|i|
      [".c#{i}", "div.c#{i}", "[data-x=\"v#{i}\"]", ".c#{i} > p.b"]
    }
    selectors = selector_sources.map {|s|
      CSS::Native::Selector.compile(CSS.parse_selector_list(s))
    }

    elements = []
    doc.traverse {|n| elements << n if n.element? }

    work = lambda {|duration|
      n = 0
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration
      loop do
        elements.each { snap.matches_any?(_1, selectors); n += 1 }
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end
      n
    }

    duration = 1.0
    single   = work.call(duration)

    threads = 4.times.map { Thread.new { work.call(duration) } }
    multi   = threads.map(&:value).sum

    ratio = multi.to_f / single
    # If GVL were held, 4 Ruby threads serialize on it and we'd see ratio
    # ≈ 1.0 (or below, due to scheduling overhead). With GVL released
    # during the match loop we expect measurable scaling. The threshold is
    # deliberately modest — small or noisy CI runners and the residual
    # GVL acquire for object_id lookup before each call cap real-world
    # scaling well short of N×. We only assert that some scaling occurs.
    assert_operator ratio, :>, 1.05,
      "expected GVL release → ratio > 1.05x, got #{ratio.round(2)}x (single=#{single}, multi=#{multi})"
  end
end

require 'etc'
