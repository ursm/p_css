require_relative '../lib/css'
require 'stackprof' if ENV['PROFILE']

# Same Tailwind-ish synthetic stylesheet as cascade_bench.rb.
def make_stylesheet
  rules = []

  rules << '* { box-sizing: border-box; }'
  rules << 'body { margin: 0; color: #333; font-family: sans-serif; }'
  rules << 'a { color: #0066cc; text-decoration: none; }'

  100.times do |i|
    rules << ".m-#{i} { margin: #{i * 0.25}rem; }"
    rules << ".p-#{i} { padding: #{i * 0.25}rem; }"
    rules << ".text-#{i} { font-size: #{0.5 + i * 0.05}rem; }"
    rules << ".bg-#{i} { background-color: hsl(#{i * 3.6}, 50%, 50%); }"
  end

  20.times do |i|
    rules << ".w-#{i * 5} { width: #{i * 5}%; }"
    rules << ".h-#{i * 5} { height: #{i * 5}%; }"
  end

  rules << '.btn:hover { background: #0055aa; }'
  rules << '.btn:disabled { opacity: 0.5; }'
  rules << '.input:focus { border-color: #0066cc; }'
  rules << '.card > .title { font-weight: 700; }'
  rules << '.card .body { padding: 1rem; }'
  rules << '.list + .list { margin-top: 1rem; }'
  rules << '.card:nth-child(odd) { background: #fafafa; }'
  rules << '.card:nth-of-type(3n+1) { color: #555; }'
  rules << '[data-state="active"] { color: blue; }'
  rules << '[data-state*="warn" i] { color: orange; }'
  rules << '[type="checkbox"]:checked { accent-color: green; }'
  rules << ':is(.btn, .link):hover { text-decoration: underline; }'
  rules << ':not(.disabled) > .clickable { cursor: pointer; }'

  rules << <<~CSS
    .panel {
      padding: 1rem;
      & .header { font-weight: bold; }
      & .body { padding-top: 0.5rem; }
      &:hover { background: #f0f0f0; }
      &.compact { padding: 0.5rem; }
    }
  CSS

  rules << "@media (min-width: 600px) { .container { max-width: 600px; } .responsive { display: flex; } .card .title { font-size: 1.25rem; } }"
  rules << "@media (min-width: 1000px) { .container { max-width: 960px; } }"

  rules.join("\n")
end

css = make_stylesheet
puts "input bytes:    #{css.bytesize}"
puts "input lines:    #{css.lines.size}"

5.times { CSS.parse_stylesheet(css) }

runs = ENV.fetch('RUNS', '20').to_i

profiler = if ENV['PROFILE']
             out = ENV.fetch('PROFILE_OUT', 'tmp/parse.dump')
             require 'fileutils'
             FileUtils.mkdir_p(File.dirname(out))
             StackProf.start(mode: :wall, raw: true, interval: 500)
             out
           end

times = []

runs.times do
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  CSS.parse_stylesheet(css)
  times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000.0
end

if profiler
  StackProf.stop
  StackProf.results(profiler)
  puts "wrote #{profiler}"
end

times.sort!
puts "parse (min):    %.2fms" % times.first
puts "parse (median): %.2fms" % times[times.size / 2]
puts "parse (max):    %.2fms" % times.last
