require_relative 'lib/css/version'

Gem::Specification.new do |spec|
  spec.name        = 'p_css'
  spec.version     = CSS::VERSION
  spec.authors     = ['Keita Urashima']
  spec.email       = ['ursm@ursm.jp']
  spec.summary     = 'A CSS Syntax Level 4 parser for Ruby, with nesting support.'
  spec.description = 'p_css is a Ruby implementation of the CSS Syntax Level 4 tokenizer and parser, including support for CSS nesting.'
  spec.homepage    = 'https://github.com/ursm/p_css'
  spec.license     = 'MIT'

  spec.metadata = {
    'bug_tracker_uri'       => "#{spec.homepage}/issues",
    'changelog_uri'         => "#{spec.homepage}/releases",
    'source_code_uri'       => spec.homepage,
    'rubygems_mfa_required' => 'true'
  }

  spec.required_ruby_version = '>= 3.4'

  spec.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE.txt']
  spec.require_paths = ['lib']
end
