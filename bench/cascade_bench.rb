require_relative '../lib/css'
require 'nokogiri'
require 'stackprof' if ENV['PROFILE']

# Synthesize a Tailwind-ish utility stylesheet plus a sprinkle of
# component / pseudo / nesting / @media rules — roughly the shape of a
# typical web app stylesheet capybara-simulated would see.
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

  rules << <<~CSS
    @media (min-width: 600px) {
      .container { max-width: 600px; }
      .responsive { display: flex; }
      .card .title { font-size: 1.25rem; }
    }
  CSS

  rules << <<~CSS
    @media (min-width: 1000px) {
      .container { max-width: 960px; }
    }
  CSS

  rules.join("\n")
end

def make_dom
  html = +'<html><body class="m-0 p-0">'

  20.times do |i|
    html << %(<div class="card panel m-#{i} p-#{i * 2} w-#{(i * 5) % 100} bg-#{i}" data-state="#{%w[active idle warn].sample}">)
    html << %(  <h2 class="title text-#{i + 5}">Card #{i}</h2>)
    html << %(  <div class="body">)
    html << %(    <p class="text-3 m-1">Card body text with some words.</p>)
    html << %(    <ul class="list">)
    5.times do |j|
      html << %(      <li class="text-2 m-#{j}">item #{j}</li>)
    end
    html << %(    </ul>)
    html << %(    <a href="#x" class="btn link m-2 p-3" data-state="active">Action</a>)
    html << %(    <input type="text" class="input m-1" placeholder="email">)
    html << %(    <input type="checkbox" checked>)
    html << %(    <input type="checkbox">)
    html << %(    <button#{i.even? ? ' disabled' : ''} class="btn m-2">Submit</button>)
    html << %(  </div>)
    html << %(</div>)
  end

  html << '</body></html>'
  Nokogiri::HTML(html)
end

# Build once
stylesheet = CSS.parse_stylesheet(make_stylesheet)
ctx        = CSS::MediaQueries::Context.default('width' => 1024)
doc        = make_dom

elements = []
doc.traverse {|n| elements << n if n.element? }

puts "stylesheet rules:        #{stylesheet.rules.size}"
puts "elements:                #{elements.size}"

# Cascade construction (one-shot, also worth profiling)
cascade = nil
build_dur = Time.now
20.times do
  cascade = CSS.cascade(stylesheet, context: ctx)
end
build_dur = (Time.now - build_dur) / 20
puts "cascade build (avg):     %.3fms" % (build_dur * 1000)

# Warmup
elements.each do |el|
  cascade.resolve(el, inline_style: el['style'])
end

# Hot loop: resolve every element. capybara-simulated's call shape.
duration = ENV.fetch('DURATION', '5').to_i
deadline = Time.now + duration
iterations = 0

profiler = if ENV['PROFILE']
             out = ENV.fetch('PROFILE_OUT', 'tmp/cascade.dump')
             require 'fileutils'
             FileUtils.mkdir_p(File.dirname(out))
             StackProf.start(mode: :wall, raw: true, interval: 500)
             out
           end

while Time.now < deadline
  elements.each do |el|
    cascade.resolve(el, inline_style: el['style'])
  end
  iterations += 1
end

if profiler
  StackProf.stop
  StackProf.results(profiler)
  puts "wrote #{profiler}"
end

total_resolves = iterations * elements.size
elapsed = duration

puts
puts "ran #{iterations} sweeps over #{elements.size} elements in #{elapsed}s"
puts "total resolves:          #{total_resolves}"
puts "throughput:              #{(total_resolves / elapsed.to_f).round(0)} resolves/s"
puts "per resolve (avg):       %.1fμs" % (elapsed * 1_000_000.0 / total_resolves)
