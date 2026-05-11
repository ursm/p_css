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

  spec.required_ruby_version = '>= 3.3'

  spec.files = Dir[
    'lib/**/*.rb',
    'sig/**/*.rbs',
    'ext/**/*.{rs,rb}',
    '**/Cargo.{toml,lock}',
    'README.md',
    'LICENSE.txt'
  ]
  spec.require_paths = ['lib']
  spec.extensions    = ['ext/css_native/extconf.rb']

  # `rb_sys` is needed at install time so extconf.rb can require
  # rb_sys/mkmf when end users compile from a source gem. cibuildgem-built
  # platform gems ship a prebuilt .so per Ruby version and bypass this
  # path, but the source gem still has to be installable.
  spec.add_dependency 'rb_sys', '~> 0.9'
end
